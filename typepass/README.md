# How to setup typepass on Gnome system




This is a python script to copy over to anywhere and run to setup a new keyring with a new key in it
Be careful, the way that gnome keyring works is that there is no deduplication of the keyrings, so
if you run the script multiple times, then it will create multiple keyrings each with a single duplcate key

For a gui to manage the keys, use `seahorse`
```
#!/usr/bin/env python3
"""
Create or update a GNOME Keyring / Secret Service collection and item.

This script avoids:
  - Seahorse
  - custom collection aliases
  - enumerating all collections
  - guessing collection D-Bus paths

It creates the collection once, saves the collection's D-Bus object path in a
small state file, and reuses that exact collection on later runs.

Default behavior:
  collection/keyring label: sudo-password
  item label:               typepassword
  lookup attrs:             application=sudo-password, name=typepassword

Lookup afterward:
  secret-tool lookup application sudo-password name typepassword
"""

import argparse
import getpass
import json
import os
import sys
from pathlib import Path

import gi

gi.require_version("Gio", "2.0")
gi.require_version("Secret", "1")

from gi.repository import Gio, GLib, Secret


DEFAULT_COLLECTION = "sudo-password"
DEFAULT_ITEM = "typepassword"
DEFAULT_SCHEMA = "local.sudo-password"

STATE_DIR = Path(
    os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")
) / "create-keyring"

STATE_FILE = STATE_DIR / "collections.json"

SECRET_SERVICE_NAME = "org.freedesktop.secrets"
SECRET_COLLECTION_INTERFACE = "org.freedesktop.Secret.Collection"


def die(message: str, exit_code: int = 1) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(exit_code)


def ask_yes_no(prompt: str, default: bool = False) -> bool:
    suffix = "[Y/n]" if default else "[y/N]"

    while True:
        answer = input(f"{prompt} {suffix} ").strip().lower()

        if not answer:
            return default

        if answer in ("y", "yes"):
            return True

        if answer in ("n", "no"):
            return False

        print("Please answer yes or no.")


def shell_quote(value: str) -> str:
    safe_chars = set(
        "abcdefghijklmnopqrstuvwxyz"
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        "0123456789"
        "-_./:"
    )

    if value and all(char in safe_chars for char in value):
        return value

    return "'" + value.replace("'", "'\"'\"'") + "'"


def make_schema(schema_name: str) -> Secret.Schema:
    return Secret.Schema.new(
        schema_name,
        Secret.SchemaFlags.NONE,
        {
            "application": Secret.SchemaAttributeType.STRING,
            "name": Secret.SchemaAttributeType.STRING,
        },
    )


def get_service() -> Secret.Service:
    # Important: do not use LOAD_COLLECTIONS.
    # Loading all collections can fail because your login.keyring is damaged.
    return Secret.Service.get_sync(Secret.ServiceFlags.NONE, None)


def load_state() -> dict:
    if not STATE_FILE.exists():
        return {}

    try:
        with STATE_FILE.open("r", encoding="utf-8") as handle:
            data = json.load(handle)

        if isinstance(data, dict):
            return data

    except (OSError, json.JSONDecodeError):
        pass

    return {}


def save_state(state: dict) -> None:
    STATE_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)

    temp_file = STATE_FILE.with_suffix(".tmp")

    with temp_file.open("w", encoding="utf-8") as handle:
        json.dump(state, handle, indent=2, sort_keys=True)
        handle.write("\n")

    os.chmod(temp_file, 0o600)
    temp_file.replace(STATE_FILE)


def state_key(collection_label: str) -> str:
    return collection_label


def get_collection_object_path(collection: Secret.Collection) -> str:
    path = collection.get_object_path()

    if not path:
        die("created collection did not return a D-Bus object path")

    return path


def collection_from_path(path: str) -> Secret.Collection | None:
    """
    Reopen a collection by D-Bus path without enumerating all collections.

    Secret.Collection.new_for_dbus_path_sync exists in C libsecret, but it is
    marked skipped for some language bindings and is not available in your
    Fedora/PyGObject environment. Secret.Collection is a Gio.DBusProxy subclass,
    so new_for_bus_sync is the portable fallback exposed by PyGObject.
    """
    try:
        collection = Secret.Collection.new_for_bus_sync(
            Gio.BusType.SESSION,
            Gio.DBusProxyFlags.NONE,
            None,
            SECRET_SERVICE_NAME,
            path,
            SECRET_COLLECTION_INTERFACE,
            None,
        )

        # Touch one property to verify that the object is usable.
        collection.get_label()
        return collection

    except (TypeError, AttributeError, GLib.Error):
        return None


def get_or_create_collection(
    service: Secret.Service,
    collection_label: str,
) -> tuple[Secret.Collection, bool]:
    state = load_state()
    key = state_key(collection_label)

    saved_path = state.get(key)

    if isinstance(saved_path, str) and saved_path.startswith("/"):
        collection = collection_from_path(saved_path)

        if collection is not None:
            return collection, False

        print(
            f"warning: saved collection path is stale or unavailable: {saved_path}",
            file=sys.stderr,
        )

    collection = Secret.Collection.create_sync(
        service,
        collection_label,
        None,  # no alias; GNOME Keyring only supports the 'default' alias
        Secret.CollectionCreateFlags.NONE,
        None,
    )

    state[key] = get_collection_object_path(collection)
    save_state(state)

    return collection, True


def find_existing_items(
    collection: Secret.Collection,
    schema: Secret.Schema,
    attributes: dict[str, str],
) -> list[Secret.Item]:
    # Search only inside the target collection, not globally.
    return list(
        collection.search_sync(
            schema,
            attributes,
            Secret.SearchFlags.UNLOCK | Secret.SearchFlags.ALL,
            None,
        )
    )


def create_or_replace_item(
    collection: Secret.Collection,
    schema: Secret.Schema,
    attributes: dict[str, str],
    item_label: str,
    secret_text: str,
) -> None:
    secret_value = Secret.Value.new(secret_text, -1, "text/plain")

    Secret.Item.create_sync(
        collection,
        schema,
        attributes,
        item_label,
        secret_value,
        Secret.ItemCreateFlags.REPLACE,
        None,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create or update a GNOME Keyring / Secret Service item.",
    )

    parser.add_argument(
        "--collection",
        default=DEFAULT_COLLECTION,
        help=f"collection/keyring label; default: {DEFAULT_COLLECTION}",
    )

    parser.add_argument(
        "--item",
        default=DEFAULT_ITEM,
        help=f"item label and lookup name; default: {DEFAULT_ITEM}",
    )

    parser.add_argument(
        "--application",
        default=DEFAULT_COLLECTION,
        help=f"application lookup attribute; default: {DEFAULT_COLLECTION}",
    )

    parser.add_argument(
        "--schema",
        default=DEFAULT_SCHEMA,
        help=f"libsecret schema name; default: {DEFAULT_SCHEMA}",
    )

    parser.add_argument(
        "--yes",
        action="store_true",
        help="overwrite an existing item without prompting",
    )

    parser.add_argument(
        "--print-lookup",
        action="store_true",
        help="print the secret-tool lookup command after success",
    )

    return parser.parse_args()


def main() -> int:
    args = parse_args()

    collection_label = args.collection.strip()
    item_label = args.item.strip()
    application = args.application.strip()
    schema_name = args.schema.strip()

    if not collection_label:
        die("--collection cannot be empty")

    if not item_label:
        die("--item cannot be empty")

    if not application:
        die("--application cannot be empty")

    if not schema_name:
        die("--schema cannot be empty")

    schema = make_schema(schema_name)

    attributes = {
        "application": application,
        "name": item_label,
    }

    try:
        service = get_service()

        collection, created_collection = get_or_create_collection(
            service=service,
            collection_label=collection_label,
        )

        existing_items = find_existing_items(
            collection=collection,
            schema=schema,
            attributes=attributes,
        )

        if existing_items:
            print(f"Item already exists: {item_label!r}")

            if not args.yes and not ask_yes_no("Overwrite it?", default=False):
                print("Left existing item unchanged.")
                return 0

            action = "Updated"
        else:
            action = "Created"

        secret_text = getpass.getpass(f"Secret value for item {item_label!r}: ")

        if not secret_text:
            die("secret value cannot be empty")

        create_or_replace_item(
            collection=collection,
            schema=schema,
            attributes=attributes,
            item_label=item_label,
            secret_text=secret_text,
        )

    except GLib.Error as exc:
        die(str(exc))

    if created_collection:
        print(f"Created collection: {collection_label}")
    else:
        print(f"Using existing collection: {collection_label}")

    print(f"{action} item: {item_label}")
    print(f"Lookup attributes: application={application} name={item_label}")

    if args.print_lookup:
        print()
        print("Lookup command:")
        print(
            "secret-tool lookup "
            f"application {shell_quote(application)} "
            f"name {shell_quote(item_label)}"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```













This is a script to auto type in a password based on Gnome Keyrings

```
#!/usr/bin/env bash
set -euo pipefail

password="$(secret-tool lookup application sudo-password name typepassword)"

if [[ -z "${password}" ]]; then
    notify-send "sudo hotkey" "No sudo password found or keyring is locked"
    exit 1
fi

sleep 0.25
printf '%s' "$password" | ydotool type --key-delay 0 --file -
```
