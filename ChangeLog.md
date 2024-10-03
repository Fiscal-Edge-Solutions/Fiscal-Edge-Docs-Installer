# Changelog

## [1.5.2] - 2024-10-03
### Enhancements
- **Increased Decimal Precision for Unit Prices**  
  Updated the unit price precision from 4 to 8 decimal places to comply with the latest ZRA specifications. This update addresses issues that previously caused invoices to fail with an 'Invalid Total Amount' error.

- **Improved Sage Evolution SQL Script**  
  Enhanced the SQL script to handle multiple partial invoices generated from a single sales order, ensuring accurate invoicing and improved compatibility with Sage Evolution.

## [1.5.0] - 2024-09-05
### Added
- Added support for managing multiple inventory branches.
This feature allows different branches, sharing the same database, to be registered as separate branches with the ZRA (Zambia Revenue Authority).
Each branch must have its own distinct warehouse to support this functionality.

### Changed


### Fixed