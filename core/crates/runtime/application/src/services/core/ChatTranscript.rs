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
pub(crate) struct TranscriptEvents(Arc<Mutex<HashMap<String, Weak<Journal>>>>);

impl TranscriptEvents {
    pub fn watch(&self, chat_id: String) -> StateFlow<Vec<ChatTranscriptChange>> {
        let mut topics = self.0.lock().expect("transcript registry");
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

    pub fn record(&self, chat_id: &str, kind: &str, timestamp: Option<i64>, message: Option<&ChatMessage>) {
        let topic = self.0.lock().expect("transcript registry").get(chat_id).and_then(Weak::upgrade);
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
