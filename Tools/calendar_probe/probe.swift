import Foundation
import EventKit
import UIKit

let store = EKEventStore()
var log = ""
func p(_ s: String) { log += s + "\n"; print(s) }
func flush() {
    let url = URL(fileURLWithPath: NSHomeDirectory() + "/Documents/probe.txt")
    try? log.write(to: url, atomically: true, encoding: .utf8)
}
let mode = CommandLine.arguments.contains("full") ? "full" : "write"

@main final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UIViewController()
        window?.makeKeyAndVisible()
        p("status before: \(EKEventStore.authorizationStatus(for: .event).rawValue)")
        let st = EKEventStore.authorizationStatus(for: .event)
        let go: (Bool, Error?) -> Void = { granted, err in
            DispatchQueue.main.async { probe(granted: granted, err: err) }
        }
        if st == .notDetermined {
            if mode == "full" { store.requestFullAccessToEvents(completion: go) }
            else { store.requestWriteOnlyAccessToEvents(completion: go) }
        } else { go(true, nil) }
        return true
    }
}

func probe(granted: Bool, err: Error?) {
    p("granted=\(granted) err=\(String(describing: err)) status=\(EKEventStore.authorizationStatus(for: .event).rawValue)")
    p("sources: \(store.sources.map { "\($0.title)/\($0.sourceType.rawValue)/\($0.sourceIdentifier)" })")
    p("calendars: \(store.calendars(for: .event).map { "\($0.title)|\($0.source?.title ?? "-")|\($0.allowsContentModifications)" })")
    p("default: \(String(describing: store.defaultCalendarForNewEvents?.title))")
    // create calendar
    let src = store.sources.first { $0.sourceType == .local } ?? store.defaultCalendarForNewEvents?.source
    p("src=\(String(describing: src?.title))")
    var cal: EKCalendar? = nil
    if let src {
        let c = EKCalendar(for: .event, eventStore: store)
        c.title = "Light Plan"; c.source = src
        do { try store.saveCalendar(c, commit: true); cal = c; p("saveCalendar OK id=\(c.calendarIdentifier)") }
        catch { p("saveCalendar ERR \(error)") }
    }
    let cid = cal?.calendarIdentifier ?? ""
    p("calendar(withIdentifier) -> \(String(describing: store.calendar(withIdentifier: cid)?.title))")
    p("calendars after: \(store.calendars(for: .event).map { $0.title })")
    if cal == nil { cal = store.defaultCalendarForNewEvents; p("fallback to default calendar \(String(describing: cal?.title))") }
    guard let cal else { flush(); return }
    let ev = EKEvent(eventStore: store)
    ev.calendar = cal; ev.title = "Свадьба · Ирина"
    ev.startDate = Date().addingTimeInterval(3600); ev.endDate = Date().addingTimeInterval(7200)
    ev.timeZone = TimeZone(identifier: "Asia/Tomsk")
    ev.availability = .busy
    ev.url = URL(string: "lightplan://shoot/abc")
    let loc = EKStructuredLocation(title: "Парк"); loc.geoLocation = CLLocation(latitude: 56.5, longitude: 84.9)
    ev.structuredLocation = loc
    do { try store.save(ev, span: .thisEvent, commit: true); p("saveEvent OK id=\(ev.eventIdentifier ?? "nil")") }
    catch { p("saveEvent ERR \(error)") }
    let id = ev.eventIdentifier ?? ""
    p("eventWithIdentifier -> \(String(describing: store.event(withIdentifier: id)?.title))")
    let pred = store.predicateForEvents(withStart: Date(), end: Date().addingTimeInterval(86400), calendars: [cal])
    p("events(matching) -> \(store.events(matching: pred).map { $0.title ?? "" })")
    // update held object
    ev.startDate = Date().addingTimeInterval(5400)
    do { try store.save(ev, span: .thisEvent, commit: true); p("update held OK") } catch { p("update held ERR \(error)") }
    // update via refetched
    if let e2 = store.event(withIdentifier: id) {
        e2.title = "changed"; do { try store.save(e2, span: .thisEvent, commit: true); p("update refetched OK") } catch { p("update refetched ERR \(error)") }
    } else { p("refetch nil -> cannot update by id") }
    // remove
    if let e3 = store.event(withIdentifier: id) {
        do { try store.remove(e3, span: .thisEvent, commit: true); p("remove refetched OK") } catch { p("remove ERR \(error)") }
    } else { p("refetch nil -> cannot remove by id") }
    // remove held
    do { try store.remove(ev, span: .thisEvent, commit: true); p("remove held OK") } catch { p("remove held ERR \(error)") }
    // remove calendar
    do { try store.removeCalendar(cal, commit: true); p("removeCalendar OK") } catch { p("removeCalendar ERR \(error)") }
    flush()
}


