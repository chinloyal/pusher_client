//
//  AuthRequestBuilder.swift
//  pusher_client
//
//  Created by Romario Chinloy on 10/27/20.
//

import PusherSwift

class AuthRequestBuilder: AuthRequestBuilderProtocol {
    let pusherAuth: PusherAuth
    
    init(pusherAuth: PusherAuth) {
        self.pusherAuth = pusherAuth
    }
    
    func requestFor(socketID: String, channelName: String) -> URLRequest? {
        var request = URLRequest(url: URL(string: pusherAuth.endpoint)!)
        request.httpMethod = "POST"
        do {
            let authRequest = AuthRequest(socket_id: socketID, channel_name: channelName)
            if(pusherAuth.headers.values.contains("application/json")) {
                request.httpBody = try JSONEncoder().encode(authRequest)
            } else {
                if var parameters = pusherAuth.params{

                    parameters["socket_id"]=authRequest.socket_id
                    parameters["channel_name"]=authRequest.channel_name
                    let parametersAsTupleArray=parameters.compactMap({(k,v)in return (k,v)})
                    

                    request.httpBody = urlEncoded(formDataSet: parametersAsTupleArray).data(using: String.Encoding.utf8)

                } else{
                    request.httpBody = authRequest.valueUrlEncoded!.data(using: String.Encoding.utf8)

                }






            }

            pusherAuth.headers.forEach { (key: String, value: String) in
                request.addValue(value, forHTTPHeaderField: key)
            }

            return request
        } catch {
            return nil
        }
    }
}
/// Encodings the key-values pairs in `application/x-www-form-urlencoded` format.
///
/// The only specification for this encoding is the [Forms][spec] section of the
/// *HTML 4.01 Specification*.  That leaves a lot to be desired.  For example:
///
/// * The rules about what characters should be percent encoded are murky
///
/// * It doesn't mention UTF-8, although many clients do use UTF-8
///
/// [spec]: <http://www.w3.org/TR/html401/interact/forms.html#h-17.13.4>
///
/// - parameter formDataSet: An array of key-values pairs
///
/// - returns: The returning string.

func urlEncoded(formDataSet: [(String, String)]) -> String {
    return formDataSet.map { (key, value) in
        return escape(key) + "=" + escape(value)
    }.joined(separator: "&")
}

/// Returns a string escaped for `application/x-www-form-urlencoded` encoding.
///
/// - parameter str: The string to encode.
///
/// - returns: The encoded string.

private func escape(_ str: String) -> String {
    // Convert LF to CR LF, then
    // Percent encoding anything that's not allow (this implies UTF-8), then
    // Convert " " to "+".
    //
    // Note: We worry about `addingPercentEncoding(withAllowedCharacters:)` returning nil
    // because that can only happen if the string is malformed (specifically, if it somehow
    // managed to be UTF-16 encoded with surrogate problems) <rdar://problem/28470337>.
    return str.replacingOccurrences(of: "\n", with: "\r\n")
        .addingPercentEncoding(withAllowedCharacters: sAllowedCharacters)!
        .replacingOccurrences(of: " ", with: "+")
}

/// The characters that are don't need to be percent encoded in an `application/x-www-form-urlencoded` value.

private let sAllowedCharacters: CharacterSet = {
    // Start with `CharacterSet.urlQueryAllowed` then add " " (it's converted to "+" later)
    // and remove "+" (it has to be percent encoded to prevent a conflict with " ").
    var allowed = CharacterSet.urlQueryAllowed
    allowed.insert(" ")
    allowed.remove("+")
    return allowed
}()