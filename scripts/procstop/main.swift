// procstop — точная идентификация и остановка экземпляра СВОЕГО исполняемого файла.
//
// Фаза 1, исправления CR-04/WR-02 (01-CODE-REVIEW, раунды 1–2): строка `ps … command=`
// — это argv процесса, который допускает подмену и не различает имена файлов с пробелами.
// Этот помощник спрашивает у ЯДРА фактический путь исполняемого файла каждого PID
// (proc_pidpath — немутабельная для процесса информация) и стартовое время процесса
// (proc_pidinfo/PROC_PIDTBSDINFO) как идентичность ЭКЗЕМПЛЯРА, исключающую re-use PID.
//
// Раунд 2, CR-04 — ГРАНИЦА БАНДЛА: цель обязана быть РОВНО
//   <канонический корень бандла>/Contents/MacOS/<одна компонента-имя файла>.
// Имя пути из аргумента проверяется как безопасный basename (без «/», «.», «..»),
// а каноническая форма (realpath, разрешает symlink/traversal) обязана совпадать со
// строкой <root>/Contents/MacOS/<basename> — внешняя цель НЕ может быть выражена
// никаким путём: traversal и symlink-побег дают несовпадение и отказ без сигнала.
//
// Раунд 3, CR-04 — КОРЕНЬ НЕПОДВИЖЕН: граница строится ЛИТЕРАЛЬНО от
// канонического корня и никогда не переопределяется symlink'ами внутри бандла.
// Каталог canonical(root)/Contents/MacOS обязан разрешаться сам в себя
// (realpath(литерал) == литерал): symlink самого MacOS или промежуточного
// Contents меняет каноническую форму → отказ rc=7 ДО перечисления процессов.
// Родитель исполняемого файла канонизируется и сравнивается с этим ЛИТЕРАЛОМ,
// а не с realpath(root/Contents/MacOS) — иначе symlink-каталог переносил бы
// авторизованную границу наружу (контрпример раунда 3: Boundary.app с
// Contents/MacOS → внешний каталог давал TERM внешней фикстуре).
//
// Раунд 2, WR-02 — ТРИ СОСТОЯНИЯ запроса пути: путь известен / PID исчез (ESRCH) /
// отказ инспекции (EACCES и прочее). Отказ больше НЕ означает «не совпало»: PID с
// нечитаемым путём классифицируется по НЕЗАВИСИМОМУ источнику — владельцу из
// proc_bsdinfo (pbi_uid/pbi_ruid/pbi_svuid). Цель выполняется от текущего
// пользователя; процесс чужого владельца целью не является, собственный процесс с
// нечитаемым путём (и любой процесс с неопределимым владельцем) — неопределённость,
// отказ инспекции (fail closed), а не «не запущен».
//
// Режимы:
//   procstop --list <bundle-root> <exe-path>               перечислить совпадающие
//   procstop --stop <bundle-root> <exe-path> <timeout-с>   TERM + ожидание выхода
// <bundle-root> — каталог .app бандла; без него цель не ограничить (CR-04).
//
// Свойства (fail closed):
//   • совпадение — ТОЧНОЕ строковое равенство пути ядра и канонического <exe-path>
//     (без regex, без префиксов; пробелы в пути не разбираются);
//   • цель — строго <canonical root>/Contents/MacOS/<basename> (см. выше);
//   • ровно ОДИН экземпляр: 0 — «не запущен», >1 — неоднозначно, сигналов нет;
//   • идентичность (PID + время старта + путь) перепроверяется НЕПОСРЕДСТВЕННО
//     перед TERM и на каждом шаге ожидания выхода; изменение — отказ;
//   • полный отказ перечисления процессов И любая неопределённость инспекции
//     (нечитаемый путь собственного/неклассифицируемого PID) — отдельный код
//     (inspection failure), а НЕ «процессов нет»;
//   • таймаут — отказ БЕЗ эскалации на KILL; ничего не запускается.
//
// Коды выхода: 0 — успех (--list: есть совпадения; --stop: подтверждён выход);
//   1 — использование/внутренняя ошибка; 2 — не удалось перечислить процессы или
//   инспекция неопределена; 3 — совпадений нет / не запущен; 4 — несколько
//   экземпляров (сигналов нет); 5 — идентичность изменилась (PID re-use), сигнал
//   не отправлен/не повторён; 6 — не вышел за таймаут; 7 — цель вне границы
//   <root>/Contents/MacOS/<basename> (traversal/symlink/составной путь).
//
// Только системные фреймворки (Darwin/libSystem), внешних зависимостей нет.
// Выходные тексты не содержат личных данных: только PID, старт и путь своего бандла.

import Foundation
import Darwin

// MARK: - Коды выхода

private let EXIT_OK: Int32 = 0
private let EXIT_INTERNAL: Int32 = 1
private let EXIT_INSPECT: Int32 = 2
private let EXIT_ABSENT: Int32 = 3
private let EXIT_AMBIGUOUS: Int32 = 4
private let EXIT_IDENTITY: Int32 = 5
private let EXIT_TIMEOUT: Int32 = 6
private let EXIT_BOUNDARY: Int32 = 7

private func emit(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private func bail(_ code: Int32, _ message: String) -> Never {
    emit(message)
    exit(code)
}

// MARK: - Канонические пути (CR-04)

/// Каноническая форма пути (realpath): ядро сообщает РАЗРЕШЁННЫЙ путь
/// (/private/var вместо /var и т.п.) — обе стороны сравниваются в одной форме.
private func canonicalPath(_ path: String) -> String {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 2)
    guard realpath(path, &buffer) != nil else { return path }
    return String(cString: buffer)
}

/// Безопасное имя исполняемого файла: РОВНО одна компонента пути, не «.»/«..».
/// Пробелы внутри имени легитимны (продукт называется «AI Usage Widget»).
private func isSafeBasename(_ name: String) -> Bool {
    if name.isEmpty { return false }
    if name.contains("/") { return false }          // составной путь/traversal
    if name == "." || name == ".." { return false } // traversal
    return true
}

/// Граница цели (CR-04, раунд 3): корень — неподвижная точка отсчёта.
/// Авторизованный каталог — ЛИТЕРАЛ canonical(<bundle-root>)/Contents/MacOS;
/// он обязан канонизироваться сам в себя (realpath(литерал) == литерал), иначе
/// symlink самого MacOS или промежуточного Contents переопределяет границу
/// наружу. Канонический родитель <exe-path> обязан быть РОВНО этим литералом
/// (а не realpath(root/Contents/MacOS) — такое сравнение пропускало symlink-
/// каталог). Существующий файл обязан разрешаться точно в литерал + basename.
/// Возвращает канонический ожидаемый путь; любое отклонение — отказ ДО
/// перечисления процессов. Каталог-родитель канонизируется отдельно от файла:
/// realpath несуществующего файла не разрешает symlink-компоненты
/// (/var → /private/var) и иначе даёт ложное несовпадение форм.
private func enforceBoundary(bundleRoot: String, rawExePath: String) -> String {
    let rootCanonical = canonicalPath(bundleRoot)
    let basename = (rawExePath as NSString).lastPathComponent
    guard isSafeBasename(basename) else {
        bail(EXIT_BOUNDARY, "FAIL: имя исполняемого файла не является безопасным basename (traversal/составной путь); сигнал НЕ отправляется.")
    }
    // Граница — литеральная конкатенация от КАНОНИЧЕСКОГО корня; не вычисляется
    // через realpath(root/Contents/MacOS), который следовал бы по symlink.
    let macosLiteral = rootCanonical + "/Contents/MacOS"
    let macosResolved = canonicalPath(macosLiteral)
    guard macosResolved == macosLiteral else {
        bail(EXIT_BOUNDARY, "FAIL: каталог Contents/MacOS разрешается в \(macosResolved), а не в \(macosLiteral) — граница бандла переопределена symlink'ом; сигнал НЕ отправляется.")
    }
    let parentCanonical = canonicalPath((rawExePath as NSString).deletingLastPathComponent)
    guard parentCanonical == macosLiteral else {
        bail(EXIT_BOUNDARY, "FAIL: цель лежит в \(parentCanonical), а не в \(macosLiteral)/<basename> — выход за границу бандла (traversal/symlink); сигнал НЕ отправляется.")
    }
    let required = macosLiteral + "/" + basename
    // Существующий файл обязан быть НЕ symlink: полная канонизация совпадает
    // с литеральной конкатенацией только для регулярного файла в MacOS.
    var st = stat()
    if lstat(rawExePath, &st) == 0 {
        let fullCanonical = canonicalPath(rawExePath)
        guard fullCanonical == required else {
            bail(EXIT_BOUNDARY, "FAIL: исполняемый файл разрешается в \(fullCanonical), а не в \(required) (symlink-побег?); сигнал НЕ отправляется.")
        }
    }
    return required
}

// MARK: - Данные ядра о процессе

private struct Instance {
    let pid: pid_t
    let startSeconds: Int64     // pbi_starttime.tv_sec — идентичность ЭКЗЕМПЛЯРА
    let startMicroseconds: Int32
    let path: String            // фактический путь исполняемого файла от ядра
}

/// Список PID всех процессов (proc_listpids); полный отказ — nil.
private func allPids() -> [pid_t]? {
    let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
    if needed <= 0 { return nil }
    var buffer = [pid_t](repeating: 0, count: Int(needed) / MemoryLayout<pid_t>.size + 16)
    for _ in 0..<4 { // процесс-таблица может расти между вызовами — ограниченные повторы
        let used = buffer.withUnsafeMutableBytes { raw in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, raw.baseAddress, Int32(raw.count))
        }
        if used <= 0 { return nil }
        if Int(used) <= buffer.count * MemoryLayout<pid_t>.size {
            let count = Int(used) / MemoryLayout<pid_t>.size
            return Array(buffer[0..<count].filter { $0 != 0 })
        }
        buffer = [pid_t](repeating: 0, count: Int(used) / MemoryLayout<pid_t>.size + 16)
    }
    return nil
}

/// Три состояния запроса пути у ядра (WR-02): nil-результат proc_pidpath — это
/// И «PID исчез», И «отказ доступа» — схлопывать их в «не совпало» нельзя.
private enum PathLookup {
    case known(String) // путь ядра известен
    case gone          // ESRCH: PID исчез — цели нет
    case denied        // EACCES/EPERM/иное при возможно живом PID — путь нечитаем
}

/// Фактический путь исполняемого файла PID от ядра. НЕ argv: подмене процессом
/// не поддаётся. errno захватывается сразу после вызова.
private func lookupKernelExecutablePath(of pid: pid_t) -> PathLookup {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 2)
    let length = buffer.withUnsafeMutableBufferPointer { pointer in
        proc_pidpath(pid, pointer.baseAddress, UInt32(pointer.count))
    }
    if length > 0 { return .known(String(cString: buffer)) }
    return errno == ESRCH ? .gone : .denied
}

/// Владелец и старт процесса (PROC_PIDTBSDINFO) — независимый от proc_pidpath
/// источник для классификации PID с нечитаемым путём (WR-02).
private struct BsdInfo {
    var uid: uid_t
    var ruid: uid_t
    var svuid: uid_t
    var zombie: Bool   // pbi_status == SZOMB (sys/proc.h: 5) — процесс ВЫШЕЛ, ждёт reap
    var comm: String   // kernel-maintained имя исполняемого файла (pbi_comm, ≤15 симв.)
    var startSeconds: Int64
    var startMicroseconds: Int32
}

private enum BsdLookup {
    case known(BsdInfo)
    case gone
    case denied
}

private func lookupBsdInfo(of pid: pid_t) -> BsdLookup {
    var info = proc_bsdinfo()
    let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
    if size > 0 {
        let comm: String = withUnsafeBytes(of: &info.pbi_comm) { raw in
            var bytes: [UInt8] = []
            for offset in 0..<raw.count {
                let byte = raw.loadUnaligned(fromByteOffset: offset, as: UInt8.self)
                if byte == 0 { break }
                bytes.append(byte)
            }
            return String(decoding: bytes, as: UTF8.self)
        }
        return .known(BsdInfo(uid: info.pbi_uid,
                              ruid: info.pbi_ruid,
                              svuid: info.pbi_svuid,
                              zombie: info.pbi_status == 5, // SZOMB, sys/proc.h
                              comm: comm,
                              startSeconds: Int64(info.pbi_start_tvsec),
                              startMicroseconds: Int32(clamping: info.pbi_start_tvusec)))
    }
    return errno == ESRCH ? .gone : .denied
}

/// Все экземпляры, чей путь ядра ТОЧНО равен expectedPath.
/// Возвращает nil при неопределённой инспекции (fail closed), а не пустой список.
/// expectedBasename — имя файла цели для независимой классификации PID с
/// нечитаемым путём (kernel pbi_comm); см. ветку .denied ниже.
private func matchingInstances(ofExactPath expectedPath: String) -> [Instance]? {
    guard let pids = allPids() else { return nil }
    let expectedBasename = (expectedPath as NSString).lastPathComponent
    let expectedComm = String(expectedBasename.prefix(15)) // pbi_comm ≤ 15 симв. (MAXCOMLEN-1)
    var matches: [Instance] = []
    let euid = geteuid()
    for pid in pids {
        switch lookupKernelExecutablePath(of: pid) {
        case .known(let path):
            guard path == expectedPath else { continue }
            // Путь совпал, но идентичность недоступна — не можем зафиксировать
            // экземпляр: отказ (fail closed), а не «не совпало».
            guard case .known(let bsd) = lookupBsdInfo(of: pid) else { return nil }
            matches.append(Instance(pid: pid, startSeconds: bsd.startSeconds,
                                    startMicroseconds: bsd.startMicroseconds, path: path))
        case .gone:
            continue // PID исчез между перечислением и запросом — цели нет
        case .denied:
            // Путь ядра нечитаем (EACCES/EPERM/ENOENT/…), PID может существовать.
            // Типичный неадверсальный случай: ENOENT для живого процесса, чей
            // бинарный файл заменён/удалён обновлением приложения (наблюдается на
            // любой реальной машине). Независимая классификация (WR-02):
            switch lookupBsdInfo(of: pid) {
            case .gone:
                continue
            case .known(let bsd):
                if bsd.zombie {
                    // Зомби (вышел, ждёт reap) ничего не исполняет и не пишет —
                    // не цель и не неопределённость.
                    continue
                }
                if bsd.uid == euid || bsd.ruid == euid || bsd.svuid == euid {
                    // Собственный процесс с нечитаемым путём: kernel-имя pbi_comm
                    // — независимый identity (НЕ argv; наш продукт progname не
                    // меняет). Несовпадение с именем цели исключает процесс;
                    // совпадение (замена бинарря нашей же сборки либо setprogname-
                    // подмена) — неопределённость: fail closed, не «не запущен».
                    if bsd.comm == expectedComm { return nil }
                    continue
                }
                continue // процесс другого владельца — не наша цель
            case .denied:
                // Владелец неопределим — исключить цель нельзя: неопределённость.
                return nil
            }
        }
    }
    return matches
}

/// Жив ли PID (сигнал 0 — разрешение, не сигнал); nil — состояние неизвестно.
private func alive(_ pid: pid_t) -> Bool? {
    if kill(pid, 0) == 0 { return true }
    if errno == ESRCH { return false }
    // EPERM и прочее: PID существует, но это уже НЕ обязательно наш экземпляр.
    return nil
}

/// Повторная сверка идентичности конкретного экземпляра (PID + старт + путь).
private func stillSameInstance(_ instance: Instance, expectedPath: String) -> Bool {
    guard case .known(let path) = lookupKernelExecutablePath(of: instance.pid),
          path == expectedPath,
          case .known(let bsd) = lookupBsdInfo(of: instance.pid),
          bsd.startSeconds == instance.startSeconds,
          bsd.startMicroseconds == instance.startMicroseconds else { return false }
    return true
}

// MARK: - Режимы

private func usage() -> Never {
    emit("использование: procstop --list <bundle-root> <exe-path> | procstop --stop <bundle-root> <exe-path> <timeout-с>")
    emit("<bundle-root> — каталог .app: цель ограничена его Contents/MacOS (CR-04).")
    exit(EXIT_INTERNAL)
}

private func runList(expectedPath: String) -> Never {
    guard let matches = matchingInstances(ofExactPath: expectedPath) else {
        bail(EXIT_INSPECT, "FAIL: не удалось перечислить процессы/пути ядра или инспекция неопределена — состояние неизвестно, сигналов нет.")
    }
    if matches.isEmpty {
        bail(EXIT_ABSENT, "не запущен: ни один процесс не имеет точного пути исполняемого файла \(expectedPath).")
    }
    for instance in matches {
        print("\(instance.pid)\t\(instance.startSeconds).\(instance.startMicroseconds)\t\(instance.path)")
    }
    exit(EXIT_OK)
}

private func runStop(expectedPath: String, timeout: Double) -> Never {
    guard let matches = matchingInstances(ofExactPath: expectedPath) else {
        bail(EXIT_INSPECT, "FAIL: не удалось перечислить процессы/пути ядра или инспекция неопределена (нечитаемый путь собственного/неклассифицируемого PID) — состояние неизвестно, замена НЕ разрешена.")
    }
    if matches.isEmpty {
        bail(EXIT_ABSENT, "не запущен: ни один процесс не имеет точного пути исполняемого файла \(expectedPath); ни одного сигнала.")
    }
    guard matches.count == 1, let instance = matches.first else {
        bail(EXIT_AMBIGUOUS, "FAIL: путь \(expectedPath) исполняют \(matches.count) процессов — неоднозначно; НИ ОДНОГО сигнала, останови лишние вручную.")
    }

    // Перепроверка НЕПОСРЕДСТВЕННО перед сигналом (окно re-use PID между
    // перечислением и TERM закрыто до минимума; страница между — ядро, не shell).
    guard stillSameInstance(instance, expectedPath: expectedPath) else {
        bail(EXIT_IDENTITY, "FAIL: PID \(instance.pid) изменил идентичность до сигнала (re-use PID?) — сигнал НЕ отправлен.")
    }
    if kill(instance.pid, SIGTERM) != 0 {
        if errno == ESRCH {
            // Процесс вышел между сверкой и сигналом — цель достигнута без нас.
            print("подтверждён фактический выход PID \(instance.pid) (завершился до TERM).")
            exit(EXIT_OK)
        }
        bail(EXIT_INTERNAL, "FAIL: TERM для PID \(instance.pid) не доставлен (errno \(errno)).")
    }
    print("TERM отправлен точному экземпляру PID \(instance.pid) (путь ядра совпал, старт \(instance.startSeconds)).")

    // Ожидание ФАКТИЧЕСКОГО выхода; таймаут = отказ без эскалации.
    // Зомби (процесс принял TERM и выходит) всё ещё числится в таблице процессов:
    // kill(pid,0) успешен, но путь ядра уже недоступен — это ВЫХОД, а не re-use PID.
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        let running = alive(instance.pid)
        if running == false {
            print("подтверждён фактический выход PID \(instance.pid).")
            exit(EXIT_OK)
        }
        if running == true {
            switch lookupKernelExecutablePath(of: instance.pid) {
            case .known(let path):
                guard path == expectedPath else {
                    bail(EXIT_IDENTITY, "FAIL: PID \(instance.pid) жив, но путь ядра изменился (re-use PID?) — повторных сигналов нет.")
                }
                guard case .known(let bsd) = lookupBsdInfo(of: instance.pid),
                      bsd.startSeconds == instance.startSeconds,
                      bsd.startMicroseconds == instance.startMicroseconds else {
                    bail(EXIT_IDENTITY, "FAIL: PID \(instance.pid) жив, но идентичность экземпляра изменилась (re-use PID?) — повторных сигналов нет.")
                }
            case .gone, .denied:
                // Жив по kill(pid,0), путь ядра недоступен (зомби/выход/отказ) —
                // ждать до ESRCH или таймаута: это НЕ смена идентичности и НЕ
                // подтверждение выхода; таймаут даст отказ (fail closed).
                break
            }
        } else {
            // kill(pid,0) вернул не успех и не ESRCH (например, EPERM): PID занят
            // процессом, который нам не принадлежит, — состояние НЕ известно; fail
            // closed, не «вышел» (WR-02).
            bail(EXIT_INSPECT, "FAIL: не удалось получить состояние PID \(instance.pid) после TERM (EPERM/иное) — состояние неизвестно, замена НЕ разрешена.")
        }
        if Date() >= deadline {
            bail(EXIT_TIMEOUT, "FAIL: PID \(instance.pid) не вышел за \(Int(timeout)) с после TERM — эскалации нет (KILL не отправляется, ничего не запускается).")
        }
        usleep(250_000)
    }
}

// MARK: - main

let arguments = CommandLine.arguments
guard arguments.count >= 4 else { usage() }
let mode = arguments[1]
let bundleRoot = arguments[2]
switch mode {
case "--list":
    guard arguments.count == 4 else { usage() }
    let expectedPath = enforceBoundary(bundleRoot: bundleRoot, rawExePath: arguments[3])
    runList(expectedPath: expectedPath)
case "--stop":
    guard arguments.count == 5, let timeout = Double(arguments[4]), timeout > 0 else { usage() }
    let expectedPath = enforceBoundary(bundleRoot: bundleRoot, rawExePath: arguments[3])
    runStop(expectedPath: expectedPath, timeout: timeout)
default:
    usage()
}
