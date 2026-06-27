const fs = require('fs');
const path = require('path');

// Định nghĩa màu sắc in ra console
const colors = {
  reset: "\x1b[0m",
  green: "\x1b[32m",
  red: "\x1b[31m",
  yellow: "\x1b[33m",
  cyan: "\x1b[36m",
  bold: "\x1b[1m"
};

console.log(`${colors.bold}${colors.cyan}=== BẮT ĐẦU KIỂM TRA CẤU HÌNH DỰ ÁN LEGADOIPA ===${colors.reset}\n`);

const projectRoot = path.resolve(__dirname, '../../../../');
const projectYmlPath = path.join(projectRoot, 'project.yml');
const buildYmlPath = path.join(projectRoot, '.github/workflows/build.yml');

let hasError = false;

function logSuccess(message) {
  console.log(`${colors.green}[OK]${colors.reset} ${message}`);
}

function logWarning(message) {
  console.log(`${colors.yellow}[WARNING]${colors.reset} ${message}`);
}

function logError(message) {
  console.log(`${colors.red}[ERROR]${colors.reset} ${message}`);
  hasError = true;
}

// 1. Kiểm tra sự tồn tại của các file cấu hình quan trọng
console.log(`${colors.bold}1. Kiểm tra sự tồn tại của tệp tin cấu hình:${colors.reset}`);
if (!fs.existsSync(projectYmlPath)) {
  logError(`Không tìm thấy tệp project.yml tại: ${projectYmlPath}`);
} else {
  logSuccess(`Đã tìm thấy tệp project.yml`);
}

if (!fs.existsSync(buildYmlPath)) {
  logError(`Không tìm thấy tệp GitHub Actions workflow tại: ${buildYmlPath}`);
} else {
  logSuccess(`Đã tìm thấy tệp .github/workflows/build.yml`);
}

if (hasError) {
  console.log(`\n${colors.red}${colors.bold}✖ KIỂM TRA THẤT BẠI: Thiếu các tệp tin cấu hình cốt lõi.${colors.reset}`);
  process.exit(1);
}

// Helper để parse YAML đơn giản (vì không có js-yaml package)
function parseSimpleYaml(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split(/\r?\n/);
  
  // Trích xuất đơn giản các key-value cấp 1 và cấp 2, hoặc danh sách target
  const targets = [];
  const packages = [];
  let name = '';
  let infoPlistFile = '';
  let currentKey = null;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    
    // Bỏ qua dòng trống và comment
    if (line.trim() === '' || line.trim().startsWith('#')) continue;

    // Lấy project name
    const nameMatch = line.match(/^name:\s*(.+)$/);
    if (nameMatch) {
      name = nameMatch[1].trim();
      continue;
    }

    // Phát hiện bắt đầu các block lớn
    if (line.startsWith('targets:')) {
      currentKey = 'targets';
      continue;
    }
    if (line.startsWith('packages:')) {
      currentKey = 'packages';
      continue;
    }
    if (line.match(/^\S+:/)) {
      currentKey = null; // Reset block lớn nếu gặp root key khác
    }

    // Phát hiện target name (thụt lề 2 spaces)
    if (currentKey === 'targets') {
      const targetMatch = line.match(/^  ([A-Za-z0-9_-]+):/);
      if (targetMatch) {
        targets.push(targetMatch[1]);
      }
      
      // Tìm cấu hình INFOPLIST_FILE trong settings của targets
      const infoPlistMatch = line.match(/INFOPLIST_FILE:\s*(.+)$/);
      if (infoPlistMatch) {
        infoPlistFile = infoPlistMatch[1].trim();
      }
    }

    // Phát hiện package name (thụt lề 2 spaces)
    if (currentKey === 'packages') {
      const packageMatch = line.match(/^  ([A-Za-z0-9_-]+):/);
      if (packageMatch) {
        packages.push(packageMatch[1]);
      }
    }
  }

  return { name, targets, packages, infoPlistFile };
}

// 2. Parse và kiểm tra nội dung project.yml
console.log(`\n${colors.bold}2. Phân tích tệp project.yml:${colors.reset}`);
const projConfig = parseSimpleYaml(projectYmlPath);

if (!projConfig.name) {
  logError(`Không tìm thấy thuộc tính 'name' trong project.yml`);
} else {
  logSuccess(`Tên Xcode Project định nghĩa trong project.yml: ${projConfig.name}`);
}

if (projConfig.targets.length === 0) {
  logError(`Không tìm thấy bất kỳ target nào được định nghĩa dưới 'targets' trong project.yml`);
} else {
  logSuccess(`Tìm thấy các targets: ${projConfig.targets.join(', ')}`);
}

// Kiểm tra thư mục Sources
const sourcesDir = path.join(projectRoot, 'Sources');
if (!fs.existsSync(sourcesDir)) {
  logError(`Không tìm thấy thư mục nguồn 'Sources' tại: ${sourcesDir}`);
} else {
  logSuccess(`Thư mục nguồn 'Sources' tồn tại`);
}

// Kiểm tra tệp Info.plist
if (!projConfig.infoPlistFile) {
  logWarning(`Không tìm thấy cấu hình INFOPLIST_FILE trong project.yml. XcodeGen sẽ tự động tạo Info.plist mặc định.`);
} else {
  const infoPlistPath = path.join(projectRoot, projConfig.infoPlistFile);
  if (!fs.existsSync(infoPlistPath)) {
    logError(`Tệp cấu hình Info.plist định nghĩa tại '${projConfig.infoPlistFile}' không tồn tại trên đĩa!`);
  } else {
    logSuccess(`Tệp cấu hình Info.plist tồn tại tại: ${projConfig.infoPlistFile}`);
  }
}

// 3. Phân tích và đối chiếu với build.yml
console.log(`\n${colors.bold}3. Đối chiếu cấu hình với .github/workflows/build.yml:${colors.reset}`);
const buildYmlContent = fs.readFileSync(buildYmlPath, 'utf8');

// Trích xuất tên project xcodeproj trong build.yml (ví dụ: -project LegadoIPA.xcodeproj)
const projectRegex = /-project\s+([A-Za-z0-9_-]+)\.xcodeproj/g;
let projMatch;
let buildProjectNames = new Set();
while ((projMatch = projectRegex.exec(buildYmlContent)) !== null) {
  buildProjectNames.add(projMatch[1]);
}

if (buildProjectNames.size === 0) {
  logWarning(`Không tìm thấy khai báo '-project <Tên>.xcodeproj' nào trong build.yml.`);
} else {
  buildProjectNames.forEach(buildProjName => {
    if (buildProjName !== projConfig.name) {
      logError(`Tên project trong build.yml (${buildProjName}.xcodeproj) không khớp với tên project định nghĩa trong project.yml (${projConfig.name})`);
    } else {
      logSuccess(`Tên project khớp nhau: ${buildProjName}.xcodeproj`);
    }
  });
}

// Trích xuất tên scheme trong build.yml (ví dụ: -scheme LegadoIPA)
const schemeRegex = /-scheme\s+([A-Za-z0-9_-]+)/g;
let schemeMatch;
let buildSchemes = new Set();
while ((schemeMatch = schemeRegex.exec(buildYmlContent)) !== null) {
  buildSchemes.add(schemeMatch[1]);
}

if (buildSchemes.size === 0) {
  logWarning(`Không tìm thấy khai báo '-scheme <Tên>' nào trong build.yml.`);
} else {
  buildSchemes.forEach(schemeName => {
    if (!projConfig.targets.includes(schemeName)) {
      logError(`Scheme '${schemeName}' được build trong build.yml không tồn tại trong danh sách target của project.yml`);
    } else {
      logSuccess(`Scheme '${schemeName}' hợp lệ (có tồn tại target tương ứng trong project.yml)`);
    }
  });
}

// Kiểm tra lệnh đóng gói .app thành .ipa
// Lệnh trong build.yml: cp -r build_output/Build/Products/Release-iphoneos/LegadoIPA.app build_output/Payload/
const appCopyRegex = /Release-iphoneos\/([A-Za-z0-9_-]+)\.app/;
const appCopyMatch = buildYmlContent.match(appCopyRegex);
if (!appCopyMatch) {
  logWarning(`Không tìm thấy lệnh copy thư mục .app (Release-iphoneos/*.app) trong build.yml.`);
} else {
  const appNameInBuild = appCopyMatch[1];
  if (!projConfig.targets.includes(appNameInBuild)) {
    logError(`Tên ứng dụng .app được copy trong build.yml (${appNameInBuild}.app) không khớp với bất kỳ target nào trong project.yml`);
  } else {
    logSuccess(`Tên ứng dụng .app đóng gói khớp hợp lệ: ${appNameInBuild}.app`);
  }
}

// 4. Kết luận
console.log(`\n${colors.bold}4. Kết luận:${colors.reset}`);
if (hasError) {
  console.log(`${colors.red}${colors.bold}✖ KIỂM TRA THẤT BẠI: Phát hiện lỗi cấu hình có thể làm lỗi build trên GitHub Actions!${colors.reset}`);
  process.exit(1);
} else {
  console.log(`${colors.green}${colors.bold}✔ KIỂM TRA THÀNH CÔNG: Mọi cấu hình đều đồng bộ và sẵn sàng build Unsigned IPA!${colors.reset}`);
  process.exit(0);
}
