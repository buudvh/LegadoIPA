---
name: check_build_unsigned_ipa
description: Kích hoạt kiểm tra cấu hình XcodeGen và GitHub Actions workflow để đảm bảo quá trình build unsigned IPA thành công.
---

# Hướng Dẫn Sử Dụng Skill Kiểm Tra Build Unsigned IPA

Skill này hỗ trợ các AI Agent tự động hóa quy trình kiểm tra tính toàn vẹn và đồng bộ giữa cấu hình XcodeGen (`project.yml`) và quy trình GitHub Actions workflow (`.github/workflows/build.yml`) để đảm bảo không bị lỗi build Unsigned IPA trên Cloud CI.

## 1. Cách Thức Hoạt Động Của Script Tự Động

Chúng ta sử dụng một script Node.js tĩnh tại `d:/1.SOURCE_CODE/LegadoIPA/.agents/skills/check_build_unsigned_ipa/scripts/check_project.js`.

### Các hạng mục kiểm tra tự động bao gồm:
- **Tồn tại tệp tin cốt lõi:** Xác thực tệp `project.yml`, `.github/workflows/build.yml`, thư mục `Sources/` và tệp `Info.plist` của target có tồn tại hay không.
- **Đồng bộ hóa Tên Project:** Tên project được gọi build trong file `.github/workflows/build.yml` qua tham số `-project <TênProject>.xcodeproj` phải hoàn toàn khớp với trường `name:` định nghĩa trong `project.yml`.
- **Hợp lệ về Scheme/Target:** Mọi target được chỉ định build bằng tham số `-scheme <TênScheme>` trong `.github/workflows/build.yml` bắt buộc phải tồn tại trong danh sách `targets` của `project.yml`.
- **Tên Đóng Gói .app:** Đường dẫn copy tệp tin `.app` trong pha đóng gói IPA của workflow phải khớp với một trong các target ứng dụng hợp lệ trong dự án.

## 2. Hướng Dẫn Kích Hoạt Kiểm Tra

### Bước 1: Chạy Script Kiểm Tra Tự Động
Chạy lệnh sau trong PowerShell hoặc Terminal để nhận báo cáo trạng thái cấu hình:

```powershell
node d:/1.SOURCE_CODE/LegadoIPA/.agents/skills/check_build_unsigned_ipa/scripts/check_project.js
```

- Nếu kết quả trả về `[OK]` cho tất cả các phần và kết luận `✔ KIỂM TRA THÀNH CÔNG`, cấu hình của bạn đã sẵn sàng và an toàn để push lên GitHub.
- Nếu có bất kỳ lỗi `[ERROR]` nào xuất hiện, script sẽ thoát với mã lỗi `1` và bạn cần sửa ngay lập tức trước khi commit.

### Bước 2: Kiểm Tra Tĩnh Mã Nguồn Swift (Bổ sung thủ công)
Vì môi trường chạy kiểm tra ở local có thể là Windows (không thể build bằng `xcodebuild`), hãy thực hiện kiểm tra mã nguồn bằng mắt hoặc các công cụ phân tích tĩnh:
1. **Kiểm tra cú pháp file Swift mới:** Đảm bảo không có lỗi thiếu dấu ngoặc hoặc sai kiểu dữ liệu bằng cách sử dụng IDE hoặc xem xét kỹ các thay đổi code gần đây.
2. **Kiểm tra Package Dependency:** Nếu bạn thêm Package mới trong `project.yml` (ví dụ ở dưới mục `packages:`), hãy đảm bảo định nghĩa đúng phiên bản (`from`, `exact`, `branch`) và khai báo đúng target sử dụng nó trong mục `dependencies:`.

## 3. Quy Trình Khắc Phục Khi Có Lỗi
- **Lỗi không khớp tên Project/Scheme:** Sửa lại tệp `.github/workflows/build.yml` hoặc `project.yml` để các tham số `-project` và `-scheme` trùng khớp với các giá trị khai báo.
- **Lỗi thiếu Info.plist:** Đảm bảo đường dẫn chỉ định ở `INFOPLIST_FILE` trong `project.yml` trỏ đúng vào một file `Info.plist` hợp lệ trên đĩa.
- **Đồng bộ CodeGraph:** Đừng quên chạy `npx.cmd @colbymchenry/codegraph sync` sau khi thay đổi bất kỳ cấu hình hay cấu trúc file nào để giữ chỉ mục CodeGraph luôn mới nhất.
