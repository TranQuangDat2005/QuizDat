# QuizDat - BYOG Edition

Ứng dụng học từ vựng với Google Sheets làm database cá nhân.

## Tính năng

- 📚 Quản lý Repository & SetCard
- 📝 Flashcards với learning states
- 📅 Calendar events
- 🔄 Offline-first với SQLite
- ☁️ Sync với Google Sheets cá nhân
- 🔐 Secure credential storage

## Cài đặt

### Yêu cầu

- Flutter SDK (3.0+)
- Google Cloud account (miễn phí)

### Chạy app

```bash
cd Front-end/QuizDat
flutter pub get
flutter run
```

## 📖 Setup Google Sheets

Xem hướng dẫn chi tiết trong app hoặc tài liệu `user_setup_guide.md`.

**Tóm tắt:**

1. Tạo Google Cloud Project
2. Enable Google Sheets API
3. Tạo Service Account & download credentials.json
4. Tạo Google Sheet mới & share với service account
5. Upload credentials vào app
6. Nhập Sheet ID
7. Hoàn tất!

## Kiến trúc

```
Flutter App → Google Sheets API → User's Personal Sheet
           ↓
      SQLite local (offline)
```
## 📱 Chạy trên thiết bị

### Android

```bash
flutter build apk
flutter install
```

### iOS

```bash
flutter build ios
# Open in Xcode to deploy
```

## 🧪 Testing

Xem `e2e_testing_guide.md` để test toàn bộ tính năng.

## 📚 Documentation

- `user_setup_guide.md` - Hướng dẫn setup cho user
- `e2e_testing_guide.md` - Test cases
- `architecture_byog.md` - Kiến trúc chi tiết
- `walkthrough.md` - Implementation walkthrough

## 🔒 Bảo mật

- Credentials được mã hóa với `flutter_secure_storage`
- Mỗi user có Sheet riêng, hoàn toàn độc lập
- Service Account authentication (Google OAuth 2.0)

## 📄 License

MIT

## 🤝 Contributing

PRs welcome!

---

**Enjoy learning! 📚✨**
