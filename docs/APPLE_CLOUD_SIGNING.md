# Signing Apple builds with your own iCloud containers

Generic unsigned releases keep CloudKit disabled. Merely re-signing one with a
different developer identity does not grant access to the original team's iCloud
containers. Use an Apple Developer Program team that supports iCloud capabilities.

1. In your Apple Developer account, register your iOS and tvOS app identifiers.
   Keep them consistent between updates to preserve each app's local data.
2. Register a shared CloudKit container owned by your team, and associate it with
   both app identifiers. Register a separate iCloud Documents container for iOS
   and associate it with the iOS identifier only.
3. Configure each existing platform build directory with your identifiers:

   ```sh
   cmake -S . -B build-ios-device \
     -DBUNDLE_ID=com.example.soh.ios -DSOH_ENABLE_ICLOUD=ON \
     -DSOH_ICLOUD_CONTAINER_ID=iCloud.com.example.soh.saves \
     -DSOH_ICLOUD_DOCUMENTS_CONTAINER_ID=iCloud.com.example.soh.documents

   cmake -S . -B build-tvos-device \
     -DBUNDLE_ID=com.example.soh.tvos -DSOH_ENABLE_ICLOUD=ON \
     -DSOH_ICLOUD_CONTAINER_ID=iCloud.com.example.soh.saves
   ```

   These commands assume the platform toolchain and SDK have already been set up
   as for the normal Apple builds. Replace example identifiers with your own.
4. Regenerate provisioning profiles. The iOS profile must authorize CloudKit,
   CloudDocuments and the Documents ubiquity identifier; tvOS needs CloudKit only.
   Build and sign using your team, certificate, and matching profiles. Keep both
   apps on the same CloudKit environment (Development or Production).
5. For Production distribution, deploy the CloudKit schema, including the
   `SOHSaveFile` record type used by the app, to Production in CloudKit Console.
   An empty or Development-only schema is not a working Production deployment.
6. Sign into the same iCloud account on both devices and enable **Sync Saves with
   iCloud** in both apps. This is separate from automatic iOS iCloud Drive mirroring.

If making an unsigned intermediate IPA for later authorized signing, use:

```sh
SOH_PACKAGE_CLOUD=provisioned scripts/package-ios-unsigned.sh /path/to/app.app /path/to/output.ipa
```

This preserves cloud support; it does not grant entitlements or include signing
credentials. The eventual signer must preserve the generated cloud entitlements
and embed a matching provisioning profile. The default packaging mode remains
`disabled` for generic sideloading. Do not enable the marker on a build compiled
for a different team's containers.

Increase the build number when changing iCloud Drive metadata. iOS may take time
to register the visible SOH folder and finish uploads. The app reports confirmed
and pending uploads separately. Keep the app open for initial large transfers.

## Apple TV LAN transfers

Use the displayed LAN address on a trusted local network. Upload saves, mods,
game archives, or JSON settings. JSON uploads must be objects, use a simple
`.json` filename, and be at most 8 MB. They are staged until the app is fully
closed and reopened; the previous file is retained in local history. Uploading a
configuration explicitly replaces that configuration at next launch. Arbitrary
paths and malformed JSON are rejected. Save downloads remain available through
the same page. No extra LAN pairing controls are required.
