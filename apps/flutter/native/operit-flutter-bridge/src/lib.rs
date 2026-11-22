#![allow(non_snake_case)]
//! Flutter's transport boundary around the platform-independent Core runtime.
//! PlatformRuntimeFactory selects host construction; PlatformRuntimeAbi selects ABI modules.

mod BridgeCodec;
mod BridgeExports;
mod BridgeRuntime;
mod BridgeTransport;
mod FlutterHostAdapters;
mod FlutterOwnerCapabilities;
mod FlutterSystemOperationBridge;
#[cfg(not(target_arch = "wasm32"))]
mod LocalRuntimeTransport;
mod PlatformRuntimeAbi;
mod PlatformRuntimeFactory;

pub use BridgeExports::*;
pub use BridgeRuntime::OperitFlutterBridge;

pub(crate) use BridgeRuntime::current_time_millis_u64;

// V8's bundled libc++ uses these newer bionic entry points even when the app
// targets API 24. Keep the app's minimum API level while providing the small
// compatibility shims required by the static V8 archive.
#[cfg(target_os = "android")]
mod android_api_compat {
    use core::ffi::{c_char, c_double, c_float, c_void};

    unsafe extern "C" {
        fn strtof(value: *const c_char, end: *mut *mut c_char) -> c_float;
        fn strtod(value: *const c_char, end: *mut *mut c_char) -> c_double;
    }

    #[no_mangle]
    pub unsafe extern "C" fn aligned_alloc(alignment: usize, size: usize) -> *mut c_void {
        if alignment == 0 || !alignment.is_power_of_two() || size % alignment != 0 {
            return core::ptr::null_mut();
        }
        let mut result = core::ptr::null_mut();
        if libc::posix_memalign(&mut result, alignment, size) == 0 {
            result
        } else {
            core::ptr::null_mut()
        }
    }

    #[no_mangle]
    pub unsafe extern "C" fn strtof_l(
        value: *const c_char,
        end: *mut *mut c_char,
        _locale: *mut c_void,
    ) -> c_float {
        strtof(value, end)
    }

    #[no_mangle]
    pub unsafe extern "C" fn strtod_l(
        value: *const c_char,
        end: *mut *mut c_char,
        _locale: *mut c_void,
    ) -> c_double {
        strtod(value, end)
    }
}
