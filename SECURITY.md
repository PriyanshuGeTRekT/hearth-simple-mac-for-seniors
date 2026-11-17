# Security policy

## Supported versions

Only the [latest release](https://github.com/PriyanshuGeTRekT/hearth-simple-mac-for-seniors/releases/latest) of Hearth receives security fixes. Please update to it and check that the problem still happens before reporting.

| Version        | Supported |
| -------------- | --------- |
| Latest release | Yes       |
| Older releases | No        |

## Reporting a vulnerability

**Please do not report security problems in public issues, discussions or pull requests.**

Report them privately through GitHub:

1. Open the [Security tab](https://github.com/PriyanshuGeTRekT/hearth-simple-mac-for-seniors/security) of this repository.
2. Click **Report a vulnerability**.
3. Describe the problem, the Hearth and macOS versions affected, and the steps to reproduce it. A proof of concept helps.

You will get a reply as soon as possible, usually within a week. Once the problem is confirmed, a fix is prepared and released, and the advisory is published with credit to you unless you prefer to stay anonymous.

## Scope

Examples of what counts as a security problem in Hearth:

- Strict mode or the PIN being bypassed by the person using the Mac in a way the README doesn't already describe.
- A setup file that, when imported, can open an unsafe link (for example `javascript:` or `file:`) or run anything.
- Hearth quitting or hiding apps in a way that loses someone's work.
- Hearth making any network request (it should make none).

Hearth is not notarized by Apple, and the "Open Anyway" step on first launch is expected. That alone is not a vulnerability.
