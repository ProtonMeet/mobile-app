use std::fmt::Display;

#[derive(Debug, Clone)]
pub struct MeetingLinkName(String);

impl MeetingLinkName {
    pub fn new(meeting_link_name: String) -> Self {
        Self(meeting_link_name)
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl From<String> for MeetingLinkName {
    fn from(meeting_link_name: String) -> Self {
        Self(meeting_link_name)
    }
}

// TODO: implement [`TryFrom`] to add validation.
impl From<&str> for MeetingLinkName {
    fn from(meeting_link_name: &str) -> Self {
        Self(meeting_link_name.to_string())
    }
}

impl From<MeetingLinkName> for String {
    fn from(meeting_link_name: MeetingLinkName) -> Self {
        meeting_link_name.0
    }
}

impl Display for MeetingLinkName {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "MeetingLinkName({})", self.0)
    }
}
