# Security Policy

## Supported Versions

The table below identifies the versions of StreetPhare that actively receive security updates and patches. 

| Version | Supported |
| ------- | --------- |
| >= 1.0.x | :white_check_mark: Yes |
| < 1.0.0 | :x: No |

We only support the latest major release. We recommend all users and contributors update their application to the most recent version available to ensure they benefit from the latest security improvements.

## Reporting a Vulnerability

**DO NOT open a public GitHub Issue to report a security vulnerability.** Public disclosure risks exposing users to threats before a fix can be deployed.

If you discover a security vulnerability or a critical flaw within StreetPhare, please report it through one of the following private channels:

1. **GitHub Private Vulnerability Reporting:** Go to the "Security" tab of this repository, click on "Advisories", and select "Report a vulnerability" to submit a confidential report directly to the core development team.
2. **Secure Email:** Send a detailed report to `security@streetphare.org` (replace with your production security email address). 

### What to Include in Your Report
To help us triage and resolve the issue efficiently, please include:
- A description of the vulnerability and its potential impact.
- Detailed step-by-step instructions to reproduce the issue (or a proof-of-concept script/exploit).
- Any specific configuration or environment details required to trigger the flaw.

### Our Response and Disclosure Process
- **Acknowledgement:** We will acknowledge receipt of your report within 48 hours.
- **Triage and Investigation:** The engineering team will investigate the issue privately to assess its severity and validate the findings.
- **Remediation:** We aim to develop, test, and release a security patch within a reasonable timeframe (typically under 30 days, depending on complexity).
- **Coordinated Disclosure:** A public security advisory along with credit to the reporter (if desired) will be published only after a fix has been successfully merged and deployed to users.

## Network Protection Philosophy

StreetPhare is built with user safety, resilience, and privacy as fundamental core principles. To ensure a secure environment for all users, the platform implements strict operational safeguards:

- **Decentralized Consensus & Anti-Spam:** The network uses multi-party verification and distributed validation thresholds. An alert or report is only propagated and displayed to the wider community once it reaches a defined consensus baseline, preventing spam, malicious data injection, or coordinate poisoning.
- **Privacy by Design:** Location tracking and session data are ephemeral. The architecture is explicitly designed to minimize the retention of personally identifiable information (PII) or telemetry, ensuring that physical movements cannot be cross-referenced or tracked over time.
- **Proactive Abuse Mitigation:** The application includes localized, automated mechanisms to detect and ignore erratic network behavior or bulk data flooding at the edge, maintaining mesh availability even under high-stress conditions.
