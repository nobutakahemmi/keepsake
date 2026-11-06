# Keepsake

Keepsake is an iPhone app for saving a video of two people. Each phone records its own camera. Later, one phone lines the two recordings up and stitches them into one video.

This version does not make phone calls. There is no account and nothing is uploaded. Videos stay on the iPhone.

You need:

- A Mac with [Xcode 15](https://apps.apple.com/app/xcode/id497799835) or newer (free from the App Store)
- Two iPhones with iOS 17 or newer
- A free Apple ID (the same one you use for the App Store)
- A cable to plug each iPhone into the Mac

A Windows or Linux computer cannot install this app. The iPhone simulator on the Mac also will not work for the test, because it does not have the camera.

## 1. Install Xcode

1. On the Mac, open the App Store and install **Xcode**.
2. Open Xcode once and let it finish installing extra tools if it asks.

## 2. Open the project

1. Download or copy this folder onto the Mac.
2. Double-click **Keepsake.xcodeproj** (the blue Xcode icon). Do not open the loose files by themselves.

## 3. Sign in with your Apple ID

1. In Xcode, open the menu **Xcode → Settings…** (on older Xcode this is **Preferences…**).
2. Click **Accounts**.
3. Click the **+** button, choose **Apple ID**, and sign in.
4. Close Settings.

## 4. Plug in the first iPhone

1. Plug the iPhone into the Mac with a cable.
2. Unlock the iPhone.
3. If the iPhone asks you to **Trust This Computer**, tap **Trust** and enter the phone passcode.

## 5. Turn on Developer Mode

iOS hides this switch until Xcode has tried to install an app. Do these steps in order.

1. On the iPhone, open **Settings → Privacy & Security**.
2. Scroll to the bottom. If you see **Developer Mode**, turn it on, restart the iPhone when it asks, then unlock it and confirm.
3. If you do **not** see Developer Mode yet, continue with the next section. Xcode will fail once, the switch will appear, and you can turn it on and try again.

## 6. Let Xcode put the app on the phone

1. At the top of the Xcode window, click the device menu (it may say “Any iOS Device” or an iPhone simulator). Choose **your iPhone**. Do not choose a simulator.
2. In the left sidebar, click the blue **Keepsake** project icon.
3. Under **TARGETS**, click **Keepsake** (not KeepsakeTests).
4. Click **Signing & Capabilities**.
5. Check **Automatically manage signing**.
6. In **Team**, choose your name. It will say **Personal Team**.
7. If Xcode says the bundle identifier is already used, change **Bundle Identifier** to something only you would use, such as `com.yourname.keepsake`. Do this on every phone you install to, and use the same identifier.
8. Press the **Run** button (the triangle at the top left), or press Command–R.

The first build takes a few minutes. Keep the iPhone unlocked.

## 7. Trust the developer certificate

The first time you open Keepsake, iOS may say the developer is not trusted and the app will not open.

1. On the iPhone, open **Settings → General → VPN & Device Management**.
2. Under the developer app heading, tap your Apple ID.
3. Tap **Trust** and confirm.
4. Open Keepsake from the home screen. If it still will not open, press Run in Xcode again.

## 8. Install it on the second iPhone

Unplug the first phone, plug in the second, and repeat sections 4 through 7. Use the same Apple ID and the same bundle identifier.

## The app stops opening after 7 days

A free Apple ID can only install an app for **7 days**. After that, the icon may still be there but it will not open. Plug the iPhone back into the Mac, open this project, choose that iPhone, and press Run again. You do not need to pay for an Apple Developer account for this test.

## Allow the camera and microphone

The first time you tap **Start Recording**, the iPhone asks for the camera and the microphone. Tap **Allow** for both. If you tapped Don’t Allow earlier, open **Settings → Keepsake** and turn Camera and Microphone on.

## Before you test with two phones

On **both** iPhones:

1. Open **Settings → General → Date & Time** and turn on **Set Automatically**. The videos are lined up by the clock, so both phones need the right time.
2. Open **Settings → General → AirDrop** and choose **Everyone for 10 Minutes**. Bluetooth and Wi‑Fi should be on. The phones should be near each other and unlocked.

## Test it

1. On both iPhones, open Keepsake and tap **Record**.
2. Type each person’s name. The name is saved with the recording.
3. At about the same moment, tap **Start Recording** on both phones. Record for about 10 seconds. Stay on this screen. Tap **Stop Recording**.
4. On phone B, tap **Clips**. Tap **Share** on the new clip, then AirDrop it to phone A.
5. On phone A, if iOS asks how to open the video, choose **Keepsake**. If it lands in Files instead, open Keepsake, tap **Clips**, tap **Import from Files**, and choose that video. **Import from Photos** works too, but AirDrop plus Files keeps the start time more reliably.
6. On phone A, tap **Make a Keepsake**.
7. Set **This phone** to phone A’s clip and **Other phone** to the clip you just imported. The screen shows both start times, including thousandths of a second.
8. If one person looks a little early or late, move **Nudge the other clip**. Each step is 0.05 seconds, and it only goes 2 seconds earlier or later. The start times do the bigger alignment.
9. Tap **Play Preview**. If **Title card** is on, the names show for the first 3 seconds, then the two clips.
10. Choose **Side by side** or **Stacked**.
11. Choose the sound. **Both** plays the two microphones together. Choose **This phone** or **Other phone** when you are in the same room, so the voices stay clear.
12. Tap **Make the Keepsake** and wait. You can lock the phone or leave Keepsake for a short time while it finishes. Tap **Cancel** to stop. A 10‑second recording takes a little while; longer recordings take longer.
13. Tap **Watch**, or open the **Tapes** tab. You should see a thumbnail of the two of you (after the title card, when that is on), the names, and the date. Tap **Play**, **Share**, or **Delete**. Delete asks you to confirm.

The preview while you record matches the saved video. You look the way the other person saw you.

If **Share** is off on a clip, the start time is not stored in the video yet. Tap **Repair**, then Share. AirDrop the repaired clip so the other phone can line the two up.

The finished video is a 1080p H.264 MP4 saved only on that iPhone. Side by side is a wide 1920×1080 frame. Stacked is a tall 1080×1920 frame. Each person fills their half. The sound is whichever microphone you chose, or both. Keepsake asks iOS to leave these videos out of iCloud backup.

## If something goes wrong

- **Developer Mode is off.** Settings → Privacy & Security → Developer Mode. Restart the iPhone, then press Run in Xcode again.
- **Untrusted Developer.** Settings → General → VPN & Device Management → Trust.
- **No signing team.** Signing & Capabilities → Team → your Personal Team.
- **The phone is not in the list.** Unlock it, tap Trust, unplug and replug the cable, and choose it in the device menu at the top of Xcode.
- **The app will not open after a week.** Plug it in and press Run again. That is the free Apple ID limit.
- **Keepsake cannot see the camera.** Settings → Keepsake → turn Camera and Microphone on. Then tap Try Again on the Record screen.
- **Share is off.** On the Clips tab, tap **Repair**, then Share. That stores the start time in the video.
- **The two people are far out of sync.** Check that both phones use automatic date and time, and that you AirDropped the original clip (Share from the Clips tab) rather than a copy that Photos re-saved.
- **There is no overlap.** The sync screen says so when the recordings do not cover the same moment. Record again, starting at about the same time.
