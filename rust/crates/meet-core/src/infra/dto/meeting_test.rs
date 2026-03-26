#[cfg(test)]
mod tests {
    use crate::{
        domain::user::models::meeting::{Meeting, MeetingType},
        infra::dto::meeting::{MeetingDto, UpcomingMeetingsResponse},
    };
    use chrono::{DateTime, Utc};
    use serde_json;

    /// Test deserializing MeetingDto with integer Unix timestamps (the error case)
    #[test]
    fn test_meeting_dto_deserialize_with_integer_timestamps() {
        let json = r#"
        {
            "ID": "test-id",
            "AddressID": "test-address-id",
            "MeetingLinkName": "TEST123",
            "MeetingName": "encrypted-name",
            "Password": "encrypted-password",
            "Salt": "salt-value",
            "SessionKey": "session-key",
            "SRPModulusID": "modulus-id",
            "SRPSalt": "srp-salt",
            "SRPVerifier": "srp-verifier",
            "StartTime": 1746518400,
            "EndTime": 1746522000,
            "RRule": "FREQ=WEEKLY",
            "Timezone": "Europe/Zurich",
            "CustomPassword": 0,
            "Type": 3
        }
        "#;

        let result: Result<MeetingDto, _> = serde_json::from_str(json);
        assert!(result.is_ok(), "Should deserialize with integer timestamps");

        let dto = result.unwrap();
        assert_eq!(dto.id, "test-id");
        assert_eq!(dto.meeting_link_name, "TEST123");
        assert!(
            dto.start_time.is_some(),
            "StartTime should be converted to string"
        );
        assert!(
            dto.end_time.is_some(),
            "EndTime should be converted to string"
        );

        // Verify the timestamps were converted to RFC3339 strings
        let start_time = dto.start_time.unwrap();
        assert!(start_time.contains("T"), "Should be RFC3339 format");
        assert!(
            start_time.contains("Z") || start_time.contains("+"),
            "Should have timezone"
        );
    }

    /// Test deserializing MeetingDto with string RFC3339 timestamps (normal case)
    #[test]
    fn test_meeting_dto_deserialize_with_string_timestamps() {
        let json = r#"
        {
            "ID": "test-id",
            "AddressID": "test-address-id",
            "MeetingLinkName": "TEST123",
            "MeetingName": "encrypted-name",
            "Password": "encrypted-password",
            "Salt": "salt-value",
            "SessionKey": "session-key",
            "SRPModulusID": "modulus-id",
            "SRPSalt": "srp-salt",
            "SRPVerifier": "srp-verifier",
            "StartTime": "2025-01-06T10:00:00Z",
            "EndTime": "2025-01-06T11:00:00Z",
            "RRule": null,
            "Timezone": null,
            "CustomPassword": 0,
            "Type": 1
        }
        "#;

        let result: Result<MeetingDto, _> = serde_json::from_str(json);
        assert!(result.is_ok(), "Should deserialize with string timestamps");

        let dto = result.unwrap();
        assert_eq!(dto.start_time, Some("2025-01-06T10:00:00Z".to_string()));
        assert_eq!(dto.end_time, Some("2025-01-06T11:00:00Z".to_string()));
    }

    /// Test deserializing MeetingDto with null timestamps (personal meetings)
    #[test]
    fn test_meeting_dto_deserialize_with_null_timestamps() {
        let json = r#"
        {
            "ID": "test-id",
            "AddressID": "test-address-id",
            "MeetingLinkName": "TEST123",
            "MeetingName": "encrypted-name",
            "Password": "encrypted-password",
            "Salt": "salt-value",
            "SessionKey": "session-key",
            "SRPModulusID": "modulus-id",
            "SRPSalt": "srp-salt",
            "SRPVerifier": "srp-verifier",
            "StartTime": null,
            "EndTime": null,
            "RRule": null,
            "Timezone": null,
            "CustomPassword": 0,
            "Type": 1
        }
        "#;

        let result: Result<MeetingDto, _> = serde_json::from_str(json);
        assert!(result.is_ok(), "Should deserialize with null timestamps");

        let dto = result.unwrap();
        assert_eq!(dto.start_time, None);
        assert_eq!(dto.end_time, None);
        assert_eq!(dto.meeting_type, 1); // Personal meeting
        assert_eq!(dto.proton_calendar, None);
        assert_eq!(dto.create_time, None);
        assert_eq!(dto.last_used_time, None);
        assert_eq!(dto.calendar_id, None);
        assert_eq!(dto.calendar_event_id, None);
    }

    /// Test deserializing UpcomingMeetingsResponse with mixed timestamp formats (real-world scenario)
    #[test]
    fn test_upcoming_meetings_response_mixed_timestamps() {
        let json = r#"
        {
            "Meetings": [
                {
                    "ID": "meeting-1",
                    "AddressID": "addr-1",
                    "MeetingLinkName": "LINK1",
                    "MeetingName": "encrypted-name-1",
                    "Password": "encrypted-password-1",
                    "Salt": "salt-1",
                    "SessionKey": "session-key-1",
                    "SRPModulusID": "modulus-1",
                    "SRPSalt": "srp-salt-1",
                    "SRPVerifier": "srp-verifier-1",
                    "StartTime": 1746518400,
                    "EndTime": 1746522000,
                    "RRule": "FREQ=WEEKLY",
                    "Timezone": "Europe/Zurich",
                    "CustomPassword": 0,
                    "Type": 3
                },
                {
                    "ID": "meeting-2",
                    "AddressID": "addr-2",
                    "MeetingLinkName": "LINK2",
                    "MeetingName": "encrypted-name-2",
                    "Password": "encrypted-password-2",
                    "Salt": "salt-2",
                    "SessionKey": "session-key-2",
                    "SRPModulusID": "modulus-2",
                    "SRPSalt": "srp-salt-2",
                    "SRPVerifier": "srp-verifier-2",
                    "StartTime": null,
                    "EndTime": null,
                    "RRule": null,
                    "Timezone": null,
                    "CustomPassword": 0,
                    "Type": 1
                }
            ],
            "Code": 1000
        }
        "#;

        let result: Result<UpcomingMeetingsResponse, _> = serde_json::from_str(json);
        assert!(
            result.is_ok(),
            "Should deserialize response with mixed timestamp formats"
        );

        let response = result.unwrap();
        assert_eq!(response.code, 1000);
        assert_eq!(response.meetings.len(), 2);

        // First meeting has integer timestamps (should be converted)
        assert!(response.meetings[0].start_time.is_some());
        assert!(response.meetings[0].end_time.is_some());

        // Second meeting has null timestamps
        assert_eq!(response.meetings[1].start_time, None);
        assert_eq!(response.meetings[1].end_time, None);
    }

    /// Test deserializing with the exact error case from the user's report
    #[test]
    fn test_meeting_dto_deserialize_exact_error_case() {
        // This is the exact JSON structure from the error message
        let json = r#"
        {
            "ID": "NudYebWw-AzichvPYsDYPVzL9RXHSqnFBVjPNBhlApzEsOz9EAqOPAGQ4erat7f_z_54nlzkYmUfCeqvv_cnNQ==",
            "AddressID": "XBTB2F1IqlGnUQ_Uz1ZSPuCnGza0Xlj0abMKky0WWRPrl5GFIy2MbC_2wj4raPdpeSfVKJPvkGVMrh2y1EijPA==",
            "MeetingLinkName": "G4M189SFPW",
            "MeetingName": "o3T/E4w5S0moBMn2FedvJW8m/iUAbvd4EuKzHgnjY0p2T05T+20I",
            "Password": "-----BEGIN PGP MESSAGE-----\nVersion: ProtonMail\n\nwcBMA3kAuqdYhx0nAQf+MU/p3dRZiCCKDeOE5dtKg/cDY9xY11e6GWLqiNJ3\nn5q+1YMS4GggK9Y9fMLvORGCuO4cx44cHbcleNWOAZF/vJscBvO2iY3eidnw\nCNmuJFyi7dNm6IKG18Ku1cBHdxQmmj2y2WZ2KcMObh12hcbAku3GsrQzDvSL\nupfg0S8Y0KdFACVKlCr6aTqDn/E1mO1eVdX41gPkMFhMR2OyFElwQOPwO4bm\nB9d2u9IiQolw2UWwI9+fBZ1wj90fRCsIUWn4yg1CxIDRvm3jlKHJg2QW3cg/\nDmebPQFw8KWGiG/HpxsFzwvZVIKfaP/3okSdEwpNHd5VmGrwzucDIavg8QcH\nxtLBNgE9WHDBDlaedX7NSmtFdsNSUHxaq68nkSTNjH2tqv2/zclFYnLzPJPV\nk2z2lB8xQKNUf1qjtwG+aXikhKYBzSXE4GTxnkvyRyF4BV1njEiuu2tpfM1G\n2JyipaqblODIcQY62DpZZ9WS181qRXBhUIFDsJ96pAqPgeCuBcNtEdOBdAYR\nJ6cPGEOFuo1mQreGTHkjsY7WVDUIYD1FkA6jwMgDJQfFh7AQgSAP71c6aHyF\nU58GVPGsMznd5uJG//5x4C59fmu55kde+KNUKfTkivGA36pObq2Pm8tHTUI3\nMmbPMFstXmjLvbyocumTGNj9bOhYw4VkAh7cljKoDBr+vjTvEtogXsMO/7ZN\nCe2lv5+kQgxcDKY1+DmARgwWHGKqNREf5B8coqKHsvvsGoe/7EZkfnwja/oV\nLkU5H/jPgq4fvu1Fng/ROV42a5bsu6vdhl3cMMkkufTrvclthGHKKbWwe8Dg\nWKzP7DkZJ54NhqEVyqdZ8QNugmW/aUctdQbjHRYHxSmNI0SCDV3h5WH/NgVD\nPrit/BvCi6UI832SZiqiV5s76Chs7hk2kXpdlerd2E2VFF+GyhKlWlJK/JVV\nmzgnuvKz6Bpr/maIsC145GGYH0kIf7pXWyFd0tnZ7j5uNCiXQzDYSmDkmW+a\neyK/dRKuReBmQQE=\n=hE6O\n-----END PGP MESSAGE-----\n",
            "CustomPassword": 0,
            "ProtonCalendar": 1,
            "Salt": "vEPVw55HH6jONjyZOYWi8Q==",
            "SessionKey": "wy4ECQMIgNDBKAhyeFz/jgSOe+TWnlAcCf4cKqm+uywlJx9KBkr8xyqJvtuY24FF",
            "SRPModulusID": "dRs2Vv64Vru392SbvvG1MbEt3Ep5P_EWz8WbHVAOl_6h_Ty9jItyktkVcfz9-xRvCGwFq_TW7i8FtJaGyFEq0g==",
            "SRPSalt": "FOhZlAZmB26fqA==",
            "SRPVerifier": "zVEEfKP2uLuPmysl21wHLflU+vu0QX7u8UWKfmFFjWXrVd2gXnZUc79D4LOuDor+6+Xrj/Hg/7clFHsH0sQPOil+sdI4of9LAEmARSlFXGyim19bdVrW8fNQvEBDEgK9yTZTGGSD6YdvmuWBfQcmbG5W/CDZ8uOG2WU43lBG7g2FxZDXIYeN5hXOR71DI9YEa4yqDF0Copg3DKDLndQ4d2fHeDwEm5/uVYnb03SKLjzhltDmnt8Fq8G5UnmCKnwwPKM26vClgpF5wVlpLvn/utiXskJNLPtbMAOUPBQrX939xH5g69QYsPEz91b4S8ZXtH7+Cyv4VVxEjbMLXz9q2w==",
            "StartTime": 1746518400,
            "EndTime": 1746522000,
            "RRule": "FREQ=WEEKLY",
            "Timezone": "Europe/Zurich",
            "Type": 3,
            "CalendarID": "BGc_Cs_qISflzGbFmE_GdHViLOeQyKiPbHqTkpgTbpiecGo61QPkxZSOzxF4WKCoZclb6p7uHfqlt9BaECVemQ==",
            "CalendarEventID": "DnR10yOhCOh1UPDaQ8yQY32YOrG3xnYBZeMMAI3b_9Ko5RPqz--mOOnvuEf0SjJcDw0PwKdf61fHAkxVcFWCTw=="
        }
        "#;

        let result: Result<MeetingDto, _> = serde_json::from_str(json);
        assert!(
            result.is_ok(),
            "Should deserialize the exact error case without failing"
        );

        let dto = result.unwrap();
        assert_eq!(dto.meeting_link_name, "G4M189SFPW");
        assert_eq!(dto.meeting_type, 3); // Recurring meeting
        assert!(
            dto.start_time.is_some(),
            "StartTime should be converted from integer"
        );
        assert!(
            dto.end_time.is_some(),
            "EndTime should be converted from integer"
        );

        // Verify timestamps are valid RFC3339 strings
        let start_time_str = dto.start_time.unwrap();
        let end_time_str = dto.end_time.unwrap();

        // Should be able to parse back to DateTime
        let start_dt = DateTime::parse_from_rfc3339(&start_time_str);
        assert!(
            start_dt.is_ok(),
            "StartTime should be valid RFC3339: {start_time_str}",
        );

        let end_dt = DateTime::parse_from_rfc3339(&end_time_str);
        assert!(
            end_dt.is_ok(),
            "EndTime should be valid RFC3339: {end_time_str}",
        );

        // Verify the converted timestamp matches the original Unix timestamp
        let start_dt_utc = start_dt.unwrap().with_timezone(&Utc);
        let expected_start = DateTime::from_timestamp(1746518400, 0).unwrap();
        assert_eq!(start_dt_utc.timestamp(), expected_start.timestamp());

        let end_dt_utc = end_dt.unwrap().with_timezone(&Utc);
        let expected_end = DateTime::from_timestamp(1746522000, 0).unwrap();
        assert_eq!(end_dt_utc.timestamp(), expected_end.timestamp());
    }

    /// Test edge case: very large timestamp values
    #[test]
    fn test_meeting_dto_deserialize_large_timestamp() {
        let json = r#"
        {
            "ID": "test-id",
            "AddressID": "test-address-id",
            "MeetingLinkName": "TEST123",
            "MeetingName": "encrypted-name",
            "Password": "encrypted-password",
            "Salt": "salt-value",
            "SessionKey": "session-key",
            "SRPModulusID": "modulus-id",
            "SRPSalt": "srp-salt",
            "SRPVerifier": "srp-verifier",
            "StartTime": 2147483647,
            "EndTime": 2147483647,
            "RRule": null,
            "Timezone": null,
            "CustomPassword": 0,
            "Type": 2
        }
        "#;

        let result: Result<MeetingDto, _> = serde_json::from_str(json);
        assert!(result.is_ok(), "Should handle large timestamp values");
    }

    /// Test edge case: zero timestamp
    #[test]
    fn test_meeting_dto_deserialize_zero_timestamp() {
        let json = r#"
        {
            "ID": "test-id",
            "AddressID": "test-address-id",
            "MeetingLinkName": "TEST123",
            "MeetingName": "encrypted-name",
            "Password": "encrypted-password",
            "Salt": "salt-value",
            "SessionKey": "session-key",
            "SRPModulusID": "modulus-id",
            "SRPSalt": "srp-salt",
            "SRPVerifier": "srp-verifier",
            "StartTime": 0,
            "EndTime": 0,
            "RRule": null,
            "Timezone": null,
            "CustomPassword": 0,
            "Type": 1
        }
        "#;

        let result: Result<MeetingDto, _> = serde_json::from_str(json);
        assert!(result.is_ok(), "Should handle zero timestamp");

        let dto = result.unwrap();
        assert!(dto.start_time.is_some());
        assert!(dto.end_time.is_some());
    }

    /// Test MeetingDto to Meeting conversion with converted timestamps
    #[test]
    fn test_meeting_dto_to_meeting_conversion() {
        let json = r#"
        {
            "ID": "test-id",
            "AddressID": "test-address-id",
            "MeetingLinkName": "TEST123",
            "MeetingName": "encrypted-name",
            "Password": "encrypted-password",
            "Salt": "salt-value",
            "SessionKey": "session-key",
            "SRPModulusID": "modulus-id",
            "SRPSalt": "srp-salt",
            "SRPVerifier": "srp-verifier",
            "StartTime": 1746518400,
            "EndTime": 1746522000,
            "RRule": "FREQ=WEEKLY",
            "Timezone": "Europe/Zurich",
            "CustomPassword": 0,
            "Type": 3
        }
        "#;

        let dto: MeetingDto = serde_json::from_str(json).unwrap();
        let meeting_result: Result<Meeting, _> = dto.try_into();

        assert!(
            meeting_result.is_ok(),
            "Should convert MeetingDto to Meeting"
        );

        let meeting = meeting_result.unwrap();
        assert_eq!(meeting.meeting_link_name, "TEST123");
        assert_eq!(meeting.meeting_type, MeetingType::Recurring);
        assert!(meeting.start_time.is_some());
        assert!(meeting.end_time.is_some());
        assert_eq!(meeting.r_rule, Some("FREQ=WEEKLY".to_string()));
        assert_eq!(meeting.time_zone, Some("Europe/Zurich".to_string()));
    }
}
