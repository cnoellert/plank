# PLANK Host Version Discovery

The client discovers the installed PLANK Host release during its
normal bookmark availability poll. The host adds this element to both HTTP and
authenticated HTTPS `/serverinfo` responses:

```xml
<PlankHostMetadataVersion>1</PlankHostMetadataVersion>
<PlankHostVersion>0.1.0-0.104</PlankHostVersion>
```

Metadata schema version 1 defines the host-version element. Its value is the
exact package release embedded in the host binary at build time. This metadata
is informational and does not replace the GameStream-compatible `appversion`,
protocol feature flags, or explicit topology version.

When a bookmark is online, the main client row displays the value immediately
to the right of `Online`. An absent or empty element is tolerated and leaves
the version portion blank. A client also ignores the release element when the
metadata schema version is absent. Offline rows do not display a stale cached
value.
