use operit_model::ChatMessage::ChatMessage;
use operit_store::PreferencesDataStore::{MutableStateFlow, StateFlow};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, Mutex, Weak};

#[derive(Clone, Debug, PartialEq, Deserialize, Serialize)]
pub struct ChatTranscriptChange {
    pub sequence: i64,
    pub kind: String,
    pub timestamp: Option<i64>,
    pub message: Option<ChatMessage>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct ChatTranscriptPage {
    pub messages: Vec<ChatMessage>,
    pub hasOlder: bool,
    pub hasNewer: bool,
}

type Journal = MutableStateFlow<Vec<ChatTranscriptChange>>;

/// A short replay buffer survives coalescing in StateFlow. The client reloads
/// around its current anchor if it falls behind the oldest retained change.
#[derive(Clone, Default)]
pub(crate) struct TranscriptEvents {
    topics: Arc<Mutex<HashMap<String, Weak<Journal>>>>,
    live: Arc<Mutex<HashMap<String, Vec<ChatMessage>>>>,
}

impl TranscriptEvents {
    pub fn watch(&self, chat_id: String) -> StateFlow<Vec<ChatTranscriptChange>> {
        let mut topics = self.topics.lock().expect("transcript registry");
        topics.retain(|_, topic| topic.strong_count() > 0);
        let topic = topics.get(&chat_id).and_then(Weak::upgrade).unwrap_or_else(|| {
            let topic = Arc::new(MutableStateFlow::new(Vec::new()));
            topics.insert(chat_id, Arc::downgrade(&topic));
            topic
        });
        topic.asStateFlow().map(move |value| {
            let _keep_topic_alive = &topic;
            value
        })
    }

    pub fn live(&self, chat_id: &str) -> Vec<ChatMessage> {
        self.live.lock().expect("live transcript registry").get(chat_id).cloned().unwrap_or_default()
    }

    pub fn clearLive(&self, chat_id: &str) {
        self.live.lock().expect("live transcript registry").remove(chat_id);
    }

    pub fn record(&self, chat_id: &str, kind: &str, timestamp: Option<i64>, message: Option<&ChatMessage>) {
        {
            let mut live = self.live.lock().expect("live transcript registry");
            if let Some(rows) = live.get_mut(chat_id) {
                rows.retain(|row| match kind {
                    "upsert" | "remove" => Some(row.timestamp) != timestamp,
                    "removeFrom" => timestamp.is_none_or(|start| row.timestamp < start),
                    _ => true,
                });
                if rows.is_empty() { live.remove(chat_id); }
            }
            if let Some(message) = message.filter(|message| message.contentStream.is_some()) {
                live.entry(chat_id.into()).or_default().push(compact(message));
            }
        }
        let topic = self.topics.lock().expect("transcript registry").get(chat_id).and_then(Weak::upgrade);
        let Some(topic) = topic else { return };
        let message = message.map(compact);
        topic.update(|journal| {
            let sequence = journal.last().map_or(1, |last| last.sequence + 1);
            if journal.len() == 24 {
                journal.remove(0);
            }
            journal.push(ChatTranscriptChange {
                sequence, kind: kind.into(), timestamp, message: message.clone(),
            });
        });
    }
}

pub(crate) fn compact(message: &ChatMessage) -> ChatMessage {
    let bytes = message.parts.iter().map(|part| {
        part.content.len() + part.attributes.iter().map(|(k, v)| k.len() + v.len()).sum::<usize>()
    }).sum::<usize>();
    if bytes <= 8192 {
        return message.clone();
    }
    ChatMessage { parts: Vec::new(), ..message.clone() }
}

pub(crate) async fn run_transcript_read<T: Send + 'static>(
    read: impl FnOnce() -> Result<T, String> + Send + 'static,
) -> Result<T, String> {
    let (send, receive) = tokio::sync::oneshot::channel();
    operit_host_api::HostManager::defaultHostRuntimeTaskSchedulerHost()
        .scheduleHostRuntimeBlockingAsyncTask("read-chat-transcript", Box::new(move || {
            Box::pin(async move { let _ = send.send(read()); })
        }))
        .map_err(|error| error.to_string())?;
    receive.await.map_err(|error| error.to_string())?
}
