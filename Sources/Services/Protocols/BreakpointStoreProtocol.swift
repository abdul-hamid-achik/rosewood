import Foundation

protocol BreakpointStoreProtocol: AnyObject {
    var breakpoints: [Breakpoint] { get }
    
    func addBreakpoint(_ breakpoint: Breakpoint)
    func removeBreakpoint(_ breakpoint: Breakpoint)
    func removeBreakpoint(at file: String, line: Int)
    func toggleBreakpoint(at file: String, line: Int)
    func hasBreakpoint(at file: String, line: Int) -> Bool
    func clearAllBreakpoints()
    func breakpoints(in file: String) -> [Breakpoint]
    func loadBreakpoints()
    func saveBreakpoints()
}
