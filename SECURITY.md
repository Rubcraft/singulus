# Security Policy

## Supported versions

Until Singulus reaches 1.0, security fixes are provided for the latest released minor version.

## Reporting a vulnerability

Please do not open a public issue for a suspected security vulnerability.

Use GitHub's private security advisory feature for the Rubcraft/singulus repository when available. Include reproduction steps, affected Ruby versions, and the expected security property.

Singulus provides runtime hardening, not a Ruby VM security boundary. Code with unrestricted ability to mutate the process or VM may bypass library-level protections.
