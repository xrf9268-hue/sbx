# Telegram Bot Remote Management

`sbx` can run a lightweight Telegram Bot daemon for remote sing-box operations.
The bot uses Telegram Bot API long polling, keeps a whitelist of allowed
`chat_id`s in `state.json`, and runs as a separate systemd service:

- Unit: `sbx-telegram-bot.service`
- Launcher: `/usr/local/bin/sbx-telegram-bot`
- Token env file: `/etc/sing-box/telegram.env`
- Offset state: `/var/lib/sbx-telegram-bot/offset`

## What It Can Do

Supported Telegram commands:

- `/status` - show whether `sing-box` is active
- `/users` - list configured users
- `/adduser <name>` - add a user, sync config, restart `sing-box`
- `/removeuser <name|uuid>` - remove a user, sync config, restart `sing-box`
- `/restart` - restart `sing-box`
- `/help` - show command list

Non-whitelisted chats get a silent drop. The bot does not reply at all, which
avoids leaking whether a given chat ID is authorized.

## BotFather Setup

1. Open Telegram and talk to [@BotFather](https://t.me/BotFather).
2. Run `/newbot` and complete the prompts.
3. Copy the generated bot token. It should look like:

```text
123456789:AAEhBP0av28FrI51bX4nFxxxxxxxxxxxxxxxxxx
```

4. Send a message to your new bot from the account or group that should manage
   the server.
5. Obtain the numeric `chat_id` you want to authorize.

Notes:

- Personal chats use a positive integer `chat_id`.
- Groups and supergroups usually use a negative integer such as
  `-1001234567890`.

## CLI Workflow

Initial setup:

```bash
sbx telegram setup
sbx telegram enable
sbx telegram status
```

Ongoing operations:

```bash
sbx telegram logs
sbx telegram admin list
sbx telegram admin add 123456789
sbx telegram admin remove 123456789
sbx telegram disable
```

`sbx telegram setup` prompts for:

- Bot token
- Initial admin `chat_id`

During setup, `sbx` calls Telegram `getMe` to validate the token before writing
anything to disk.

## Permission Model

The bot runs as `root` because the delegated operations already require root:

- mutating users in `state.json`
- regenerating sing-box config
- restarting `sing-box`

Authorization is separate from Unix permissions:

- The service may run as `root`
- Only `chat_id`s listed in `.telegram.admin_chat_ids` are allowed to issue
  bot commands

State tracked in `state.json`:

- `.telegram.enabled`
- `.telegram.username`
- `.telegram.admin_chat_ids`

The bot token is kept in `/etc/sing-box/telegram.env` instead of being placed
on the systemd command line.

## Troubleshooting

Check service status and logs:

```bash
sbx telegram status
sbx telegram logs
journalctl -u sbx-telegram-bot -n 80 --no-pager
```

Common issues:

- `setup` fails immediately: the token format is invalid or `getMe` rejected it
- `enable` fails: `/usr/local/bin/sbx-telegram-bot` or
  `/etc/sing-box/telegram.env` is missing
- bot receives messages but does nothing: the sending chat is not present in
  `admin_chat_ids`
- `/adduser` or `/removeuser` succeeds in Telegram but clients do not refresh:
  inspect `sbx telegram logs` and `journalctl -u sing-box`

## Security Notes

- Files written by the Telegram feature are root-owned
- The token env file is written with mode `600`
- Offset/state writes use atomic replace patterns
- The command dispatcher never `eval`s Telegram input
