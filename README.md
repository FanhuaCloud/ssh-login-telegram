# SSH 登录 Telegram 通知

在 Debian 13 服务器上安装 SSH 登录通知脚本。新的 SSH 会话建立后，脚本会向指定的 Telegram 聊天发送服务器、登录用户、来源地址和时间。

## 安装前准备

- 一台运行 **Debian 13** 的服务器。安装脚本目前只支持 Debian 13。
- SSH 服务启用了 PAM（`UsePAM yes`）。安装程序会检查这一项。
- 一个 Telegram Bot Token 和一个数字格式的 Chat ID。

可以通过 Telegram 的 `@BotFather` 创建机器人并取得 Bot Token。先向机器人发送一条消息，再使用 Telegram Bot API 或合适的工具查出对话的 Chat ID。群组的 Chat ID 通常是负数；安装程序接受带负号的数字。

## 下载

将下面命令中的 `YOUR_GITHUB_USERNAME/YOUR_REPOSITORY` 替换为实际的 GitHub 用户名和仓库名。若默认分支不是 `main`，也请相应修改分支名。

```bash
curl -fL -o install.sh https://raw.githubusercontent.com/FanhuaCloud/ssh-login-telegram/main/install.sh
```

也可以在电脑上从项目页面下载 `install.sh`，再将文件上传到服务器。下载后可以先检查脚本内容：

```bash
less install.sh
```

## 执行

在服务器上进入 `install.sh` 所在目录，然后运行：

```bash
sudo bash install.sh
```

安装程序会依次提示输入：

1. **Telegram Bot Token**：输入时不会显示在屏幕上。
2. **Telegram Chat ID**：输入数字；群组 ID 可以是负数。
3. **服务器备注**：可直接按 Enter 使用服务器主机名。

程序以 root 权限安装通知脚本和配置，并在 `/etc/pam.d/sshd` 中启用 SSH 会话通知。若系统没有 `curl`，安装程序会尝试通过 `apt` 安装。安装成功后无需重启 sshd；新建一条 SSH 连接即可测试。

## 安装位置与安全

- 配置文件：`/etc/ssh-login-notify/telegram.conf`（仅 root 可读）
- 通知脚本：`/usr/local/sbin/ssh-login-telegram.sh`
- PAM 设置：`/etc/pam.d/sshd`
- 修改前的 PAM 备份：安装成功时会显示备份目录，路径位于 `/var/backups/ssh-login-notify.*`

Bot Token 相当于机器人的凭据，请勿分享或提交到代码仓库。安装程序会将 Token 存入仅 root 可读的配置文件。若发现已有安装或残留的部分安装，脚本会停止，不会覆盖已有文件；请先检查现有配置再处理。

## 卸载

在服务器上执行下面这一条命令。它会从 `/etc/pam.d/sshd` 删除本工具添加的标记和规则，然后删除通知脚本与配置文件；若配置目录中还有其他文件，`rmdir` 会保留该目录并提示失败。

```bash
sudo sed -i '/^# ssh-login-notify:/d;/^session optional pam_exec\.so quiet type=open_session \/usr\/local\/sbin\/ssh-login-telegram\.sh$/d' /etc/pam.d/sshd && sudo rm -f /usr/local/sbin/ssh-login-telegram.sh /etc/ssh-login-notify/telegram.conf && sudo rmdir /etc/ssh-login-notify
```

## 排查

- 确认服务器运行 Debian 13，且使用 `sudo` 执行。
- 确认 `/etc/pam.d/sshd` 存在，并且 SSH 的 `UsePAM` 已启用。
- 确认服务器可以访问 Telegram API，Bot Token 与 Chat ID 正确。
- 登录通知发送失败时，可在服务器查看系统日志：

  ```bash
  journalctl -t ssh-telegram
  ```
