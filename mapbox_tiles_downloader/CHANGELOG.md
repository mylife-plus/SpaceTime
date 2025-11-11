# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2024-01-15

### Added
- Initial release
- Core tile downloader with Mapbox API integration
- Cron job scheduler for automated downloads
- State management for tracking progress
- Quota management with automatic fallback to smaller tiles
- Resume support for interrupted downloads
- Concurrent download support with configurable parallelism
- Retry logic for failed downloads
- Rate limit handling
- Status reporter with detailed statistics
- Reset utility for state and tile management
- Configuration via JSON file
- Support for multiple zoom levels
- Support for custom geographic bounds
- Download history tracking
- Comprehensive documentation (README, QUICKSTART)
- Test script for configuration validation

### Features
- **Automated Scheduling**: Run downloads on a cron schedule
- **Smart Quota Management**: Automatically switch to 256px tiles when quota exceeded
- **Resume Downloads**: Continue from where you left off
- **Parallel Downloads**: Download multiple tiles simultaneously
- **Progress Tracking**: Detailed statistics and history
- **Flexible Configuration**: Easy JSON-based configuration
- **Multiple Styles**: Support for all Mapbox styles (streets, satellite, etc.)

### Technical Details
- Node.js based application
- No external database required
- JSON-based state persistence
- TMS-compatible tile structure
- Modular architecture with separate utilities
- Error handling and retry logic
- Rate limit detection and handling

## Future Enhancements

### Planned for v1.1.0
- [ ] Web dashboard for monitoring downloads
- [ ] Email notifications on completion/errors
- [ ] Support for multiple regions in one config
- [ ] Tile validation and integrity checks
- [ ] Bandwidth throttling options
- [ ] Export statistics to CSV/JSON
- [ ] Docker support
- [ ] API endpoint for remote control

### Planned for v1.2.0
- [ ] Support for vector tiles
- [ ] Tile optimization and compression
- [ ] Incremental updates for existing tiles
- [ ] Multi-region priority queue
- [ ] Advanced scheduling (time windows, bandwidth limits)
- [ ] Integration with cloud storage (S3, GCS)

### Planned for v2.0.0
- [ ] Web UI for configuration
- [ ] Real-time progress monitoring
- [ ] Multi-user support
- [ ] Database backend option
- [ ] Distributed downloading across multiple machines
- [ ] Advanced analytics and reporting

## Version History

- **1.0.0** (2024-01-15) - Initial release

## Migration Guide

### From Manual Downloads to Automated

If you were previously downloading tiles manually:

1. Install the downloader: `npm install`
2. Configure your area in `config.json`
3. Run initial download: `npm start`
4. Enable cron: `npm run cron`

### Upgrading from Future Versions

Upgrade instructions will be added here for future versions.

## Breaking Changes

None yet - this is the initial release.

## Known Issues

None currently. Please report issues on the project repository.

## Contributors

- Initial development and release

## License

MIT License - See LICENSE file for details

