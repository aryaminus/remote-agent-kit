# Telegram setup (5 min, OPTIONAL)

Skip this whole page if the Perch phone app is enough — the gateway API
works without any bot. Both `./scripts/start.sh` and `bash ~/finish.sh`
offer Telegram as an opt-in step, and the Ansible role skips cleanly when
no token is set (re-run `--tags telegram` anytime to add it later).

The gateway uses **polling**: it dials out to Telegram, so the firewall needs
**no inbound ports** at all.

1. Open Telegram, message `@BotFather`, send `/newbot`, follow the prompts
   (name + username ending in `bot`). Copy the token → `TELEGRAM_BOT_TOKEN`.
2. Message `@userinfobot`. Copy your **numeric** id → `TELEGRAM_ALLOWED_USERS`.
   Your @handle will NOT work here.
3. More than one person? Comma-separate ids: `11111,22222`. Everyone else is
   ignored by the bot — the allow-list is the access control.
4. Deploy (`make deploy` writes both values to the server env, mode 0600).
5. Test: message the bot `hello`. Debug:
   `journalctl --user -u hermes-gateway -n 100` on the server.

Rotating a leaked token: `/revoke` via @BotFather, update `.env`, re-run the
telegram role: `ansible-playbook -i ansible/inventory/hosts.yml ansible/playbook.yml --tags telegram`.
