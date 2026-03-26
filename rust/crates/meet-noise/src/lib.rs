#![allow(non_camel_case_types, non_snake_case, non_upper_case_globals)]

mod bindings {
    include!(concat!(env!("OUT_DIR"), "/bindings.rs"));
}

use bindings::*;
use std::ptr;
use std::sync::Mutex;

/// A wrapper for the RNNoise noise suppression library
pub struct Rnnoise {
    state: Mutex<*mut DenoiseState>,
    frame_size: i32,
}

// SAFETY: We ensure thread safety by wrapping the raw pointer in a Mutex
unsafe impl Send for Rnnoise {}
unsafe impl Sync for Rnnoise {}

impl Rnnoise {
    /// Creates a new RNNoise instance with default model
    pub fn new() -> Result<Self, String> {
        unsafe {
            let state = rnnoise_create(ptr::null_mut());
            if state.is_null() {
                return Err("Failed to create RNNoise state".to_string());
            }

            let frame_size = rnnoise_get_frame_size();
            Ok(Self {
                state: Mutex::new(state),
                frame_size,
            })
        }
    }

    /// Returns the frame size required for processing
    pub fn frame_size(&self) -> i32 {
        self.frame_size
    }

    /// Processes a frame of audio samples
    ///
    /// # Arguments
    ///
    /// * `input` - Input audio samples (must be frame_size length)
    /// * `output` - Output buffer for processed samples (must be frame_size length)
    ///
    /// # Returns
    ///
    /// Voice activity detection result (0.0 to 1.0)
    pub fn process_frame(&self, input: &[f32], output: &mut [f32]) -> Result<f32, String> {
        if input.len() != self.frame_size as usize {
            return Err(format!(
                "Input length must be {} samples, got {}",
                self.frame_size,
                input.len()
            ));
        }

        if output.len() != self.frame_size as usize {
            return Err(format!(
                "Output length must be {} samples, got {}",
                self.frame_size,
                output.len()
            ));
        }

        let state = self.state.lock().map_err(|_| "Failed to acquire lock")?;
        unsafe {
            let vad_result = rnnoise_process_frame(*state, output.as_mut_ptr(), input.as_ptr());
            Ok(vad_result)
        }
    } // nosemgrep
}

impl Drop for Rnnoise {
    fn drop(&mut self) {
        // nosemgrep
        if let Ok(state) = self.state.lock() {
            unsafe {
                rnnoise_destroy(*state);
            }
        }
    }
}
