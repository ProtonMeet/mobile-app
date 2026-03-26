use crux_core::{render::Render, App, CapabilityContext, Model};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct View {
    pub is_authenticated: bool,
    pub display_name: Option<String>,
    pub connecting: bool,
    pub error: Option<String>,
}

#[derive(Default, Clone, Debug)]
pub struct MyModel {
    is_authenticated: bool,
    display_name: Option<String>,
    connecting: bool,
    error: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum Event {
    // UI
    LoginRequested { username: String, password: String },
    LogoutRequested,
    // Platform responses
    LoginSucceeded { display_name: String },
    LoginFailed { message: String },
    ConnectionChanged { connected: bool },
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum Effect {
    PerformLogin { username: String, password: String },
    Disconnect,
}

pub struct CoreApp;

impl App for CoreApp {
    type Model = MyModel;
    type Event = Event;
    type Effect = Effect;
    type ViewModel = View;

    fn update(
        &self,
        model: &mut Self::Model,
        event: Self::Event,
        _caps: &CapabilityContext<Self::Effect>,
    ) -> Render<Self::Model, Self::ViewModel> {
        use Event::*;
        let mut r = Render::default();

        match event {
            LoginRequested { username, password } => {
                model.connecting = true;
                r = r.effect(Effect::PerformLogin { username, password });
            }
            LoginSucceeded { display_name } => {
                model.is_authenticated = true;
                model.display_name = Some(display_name);
                model.connecting = false;
                model.error = None;
            }
            LoginFailed { message } => {
                model.is_authenticated = false;
                model.connecting = false;
                model.error = Some(message);
            }
            LogoutRequested => {
                model.is_authenticated = false;
                model.display_name = None;
                model.error = None;
                r = r.effect(Effect::Disconnect);
            }
            ConnectionChanged { connected } => {
                model.connecting = !connected;
            }
        }

        r.view(View {
            is_authenticated: model.is_authenticated,
            display_name: model.display_name.clone(),
            connecting: model.connecting,
            error: model.error.clone(),
        })
    }
}
