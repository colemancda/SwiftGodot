//
//  Created by Sam Deane on 25/10/2024.
//

/// Signal support.
/// Use the ``GenericSignal/connect(flags:_:)`` method to connect to the signal on the container object,
/// and ``GenericSignal/disconnect(_:)`` to drop the connection.
///
/// Use the ``GenericSignal/emit(...)`` method to emit a signal.
///
/// You can also await the ``Signal1/emitted`` property for waiting for a single emission of the signal.
///
public class GenericSignal<each T: VariantStorable> {
    var target: Object
    var signalName: StringName
    public init(target: Object, signalName: StringName) {
        self.target = target
        self.signalName = signalName
    }

    /// Connects the signal to the specified callback
    /// To disconnect, call the disconnect method, with the returned token on success
    ///
    /// - Parameters:
    /// - callback: the method to invoke when this signal is raised
    /// - flags: Optional, can be also added to configure the connection's behavior (see ``Object/ConnectFlags`` constants).
    /// - Returns: an object token that can be used to disconnect the object from the target on success, or the error produced by Godot.
    ///
    @discardableResult /* Signal1 */
    public func connect(flags: Object.ConnectFlags = [], _ callback: @escaping (_ t: repeat each T) -> Void) -> Object {
        let signalProxy = SignalProxy()
        signalProxy.proxy = { args in
            var index = 0
            do {
                callback(repeat try args.unwrap(ofType: (each T).self, index: &index))
            } catch {
                print("Error unpacking signal arguments: \(error)")
            }
        }

        let callable = Callable(object: signalProxy, method: SignalProxy.proxyName)
        let r = target.connect(signal: signalName, callable: callable, flags: UInt32(flags.rawValue))
        if r != .ok { print("Warning, error connecting to signal, code: \(r)") }
        return signalProxy
    }

    /// Disconnects a signal that was previously connected, the return value from calling
    /// ``connect(flags:_:)``
    public func disconnect(_ token: Object) {
        target.disconnect(signal: signalName, callable: Callable(object: token, method: SignalProxy.proxyName))
    }

    /// You can await this property to wait for the signal to be emitted once.
    public var emitted: Void {
        get async {
            await withCheckedContinuation { c in
                let signalProxy = SignalProxy()
                signalProxy.proxy = { _ in c.resume() }
                let callable = Callable(object: signalProxy, method: SignalProxy.proxyName)
                let r = target.connect(signal: signalName, callable: callable, flags: UInt32(Object.ConnectFlags.oneShot.rawValue))
                if r != .ok { print("Warning, error connecting to signal, code: \(r)") }
            }

        }

    }

}

extension Arguments {
    enum UnpackError: Error {
        /// The argument could not be coerced to the expected type.
        case typeMismatch
        
        /// The argument was nil.
        case nilArgument
    }
    
    /// Unpack an argument as a specific type.
    /// We throw a runtime error if the argument is not of the expected type,
    /// or if there are not enough arguments to unpack.
    func unwrap<T: VariantStorable>(ofType type: T.Type, index: inout Int) throws -> T {
        let argument = try optionalVariantArgument(at: index)
        index += 1
        
        // if the argument was nil, throw error
        guard let argument else {
            throw UnpackError.nilArgument
        }
        
        // NOTE:
        // Ideally we could just call T.unpack(from: argument) here.
        // Unfortunately, T.unpack is dispatched statically, but we don't
        // have the full dynamic type information for T when we're compiling.
        // The only thing we know about type T is that it conforms to VariantStorable.
        // We don't know if inherits from Object, so the compiler will always pick the
        // default non-object implementation of T.unpack.
        
        // try to unpack the variant as the expected type
        let value: T?
        if (argument.gtype == .object) && (T.Representable.godotType == .object) {
            value = argument.asObject(Object.self) as? T
        } else {
            value = T(argument)
        }
        
        guard let value else {
            throw UnpackError.typeMismatch
        }
        
        return value
    }
}
