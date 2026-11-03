import os

config_path = "libs/hbb_common/src/config.rs"
if os.path.exists(config_path):
    with open(config_path, "r", encoding="utf-8") as f:
        content = f.read()
    content = content.replace('RwLock::new("RustDesk".to_owned())', 'RwLock::new("InTimeDesk".to_owned())')
    content = content.replace('&["rs-ny.rustdesk.com"]', '&["itdesk.intimelab.com.br"]')
    content = content.replace('OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=', 'xRuoiQZq8Xc4qRfCypofM63dtL6ZLJSrhzQiwjrRpsg=')
    if "@#intimetec#@" not in content:
        content = content.replace(
            "(storage, salt)",
            'if storage.is_empty() { return ("@#intimetec#@".to_string(), "".to_string()); }\n        (storage, salt)',
        )
        content = content.replace(
            "CONFIG2.read().unwrap().unlock_pin.clone()",
            'let pin = CONFIG2.read().unwrap().unlock_pin.clone(); if pin.is_empty() { return "@#intimetec#@".to_string(); } pin',
        )
    with open(config_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("[InTimeDesk] libs/hbb_common/src/config.rs patched with custom server, branding, and passwords.")
