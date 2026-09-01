use anyhow::{Context, Result};
use qrcode::{Color, QrCode};
use serde::Deserialize;
use serde_json::json;

use crate::http::{self, Retry};

pub struct PairingClient {
    http: reqwest::blocking::Client,
    url: String,
}

fn device_label() -> Option<String> {
    let from_file = |path: &str| {
        std::fs::read_to_string(path)
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
    };
    from_file("/sys/devices/soc0/machine").or_else(|| from_file("/etc/hostname"))
}

#[derive(Debug, Clone, Deserialize)]
pub struct PairingStart {
    #[serde(rename = "userCode")]
    pub user_code: String,
    #[serde(rename = "deviceCode")]
    pub device_code: String,
    #[serde(rename = "verificationUrl")]
    pub verification_url: String,
    #[serde(rename = "verificationUrlComplete")]
    pub verification_url_complete: String,
    #[serde(rename = "expiresIn")]
    pub expires_in: u64,
    pub interval: u64,
}

#[derive(Debug, Clone)]
pub enum PairingStatus {
    Pending,
    Approved(String),
    Expired,
}

#[derive(Deserialize)]
struct PollResponse {
    status: String,
    token: Option<String>,
}

impl PairingClient {
    pub fn new(url: impl Into<String>) -> Self {
        Self {
            http: http::blocking_client(),
            url: url.into(),
        }
    }

    fn call(&self, body: serde_json::Value, retry: Retry) -> Result<serde_json::Value> {
        http::send_json("pairing failed", retry, || {
            self.http.post(&self.url).json(&body)
        })
    }

    pub fn start(&self) -> Result<PairingStart> {
        let value = self.call(
            json!({ "op": "start", "label": device_label() }),
            Retry::OnColdStart,
        )?;
        serde_json::from_value(value).context("parsing pairing start response")
    }

    pub fn poll(&self, user_code: &str, device_code: &str) -> Result<PairingStatus> {
        let value = self.call(
            json!({
                "op": "poll",
                "userCode": user_code,
                "deviceCode": device_code,
            }),
            Retry::Never,
        )?;
        let parsed: PollResponse =
            serde_json::from_value(value).context("parsing pairing poll response")?;

        match parsed.status.as_str() {
            "approved" => {
                let token = parsed
                    .token
                    .context("pairing was approved but no token was returned")?;
                Ok(PairingStatus::Approved(token))
            }
            "expired" => Ok(PairingStatus::Expired),
            _ => Ok(PairingStatus::Pending),
        }
    }
}

pub fn qr_matrix(data: &str) -> Result<serde_json::Value> {
    let code = QrCode::new(data.as_bytes()).context("encoding the pairing URL as a QR code")?;
    let modules: String = code
        .to_colors()
        .iter()
        .map(|color| if *color == Color::Dark { '1' } else { '0' })
        .collect();

    Ok(json!({ "size": code.width(), "modules": modules }))
}
