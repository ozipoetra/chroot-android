# chroot-android

A simple Bash script collection to install and run Linux rootfs distributions (Alpine Linux, Ubuntu, Debian, and more) on **rooted Android devices** using **chroot**.

This project focuses on performance, simplicity, and flexibility.

---

## 🚀 Features

- Install popular Linux rootfs easily:
  - Alpine Linux
  - Ubuntu
  - Debian
  - (More coming soon)
- Run systems using **chroot** for near-native performance
- Automatic mount handling (proc, sys, dev, etc)
- Optional Termux integration for better file access and tooling

---

## 📱 Requirements

- ✅ Rooted Android device
- ✅ BusyBox or coreutils (recommended)
- ✅ Bash shell
- Termux (Optional, but recommended)

---

## 📂 Optional: Termux Integration

If you use Termux, you can:

- Access the chroot filesystem easily
- Shared `workspace` directory on your termux home directory. This make you to allow opening your project through app like Acode Code Editor and etc.

## ⚡ Why chroot instead of proot?

| Feature | chroot | proot (Termux default) |
|--------|-------|----------------|
| Performance | 🚀 Near native | 🐢 Slower (emulated syscalls) |
| Kernel access | ✅ Direct | ❌ Limited |
| System compatibility | ✅ Full | ⚠️ Some packages break |
| Docker/system services | ✅ Works (mostly) | ❌ Usually broken |
| File IO speed | ⚡ Fast | 🐌 Slower |

### ✔ Advantages of chroot

- Real Linux environment (not emulated)
- Much faster execution
- Better compatibility with binaries
- Works closer to real VPS/Linux server
- Can run heavy tools (databases, compilers, etc)

### ❗ Note

chroot requires root access — but gives much better results.

---

## 📦 Supported RootFS

- Alpine Linux
- Ubuntu
- Debian

---

## 🔧 Installation (example)

soon

---

## ▶ Running

```bash
sudo ./start.sh alpine
```

---

## 🛑 Stop

```bash
sudo ./stop.sh alpine
```

---

## 📖 Notes

* Make sure your Android kernel supports required mounts
* Some ROMs may need SELinux permissive mode

