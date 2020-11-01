# pusher_client


# Resolve common issues

## iOS doesn't log when enableLogging is set to true

iOS logging doesn't seem to output to flutter console, however if you run the
app from Xcode you should be able to see the logs.


## Subscribing to private channels with iOS

If using a local pusher server but are unable to subscribe to a private channel
then add this to your ios/Runner/Info.plist:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

If you know which domains you will connect to add:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>example.com</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
            <key>NSIncludesSubdomains</key>
            <true/>
        </dict>
    </dict>
</dict>
```