use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
pub struct Snapshot {
    pub schema: u32,
    pub sections: Vec<Section>,
    pub fields: Vec<Field>,
    #[serde(default)]
    pub actions: Vec<Action>,
}

#[derive(Debug, Deserialize)]
pub struct Section {
    pub id: String,
    pub label: String,
}

#[derive(Debug, Deserialize)]
pub struct Field {
    pub id: String,
    pub section: String,
    pub label: String,
    pub kind: String,
    pub value: Option<String>,
    pub origin: String,
    pub options: Vec<Choice>,
    pub editable: bool,
    pub description: String,
    pub has_value: bool,
}

#[derive(Debug, Deserialize)]
pub struct Choice {
    pub value: String,
    pub label: String,
}

#[derive(Debug, Deserialize)]
pub struct Action {
    pub id: String,
    pub section: String,
    pub label: String,
    pub inputs: Vec<ActionInput>,
}

#[derive(Debug, Deserialize)]
pub struct ActionInput {
    pub id: String,
    pub label: String,
    pub kind: String,
}

#[derive(Debug, Serialize)]
pub struct ApplyRequest {
    pub schema: u32,
    pub changes: Vec<Change>,
    pub actions: Vec<ActionRequest>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ActionRequest {
    pub id: String,
    pub values: std::collections::BTreeMap<String, String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Change {
    pub id: String,
    pub op: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
}
