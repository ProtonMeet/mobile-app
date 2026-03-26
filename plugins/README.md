# Flutter Plugins

This directory contains Flutter plugins and shared components for the Proton Meet application.

## Purpose

- Build and maintain reusable Flutter plugins
- Create wrapper implementations for external plugins (e.g., permissions handling)
- Share common components across Proton applications
- Enable code reuse between Proton Meet and Proton Meet applications

## Structure

Each plugin should be organized in its own directory with the following structure:

- `lib/` - Dart source code
- `example/` - Example implementation
- `test/` - Unit and integration tests
- `README.md` - Plugin-specific documentation
- `pubspec.yaml` - Plugin dependencies and metadata

## Creating a New Plugin

To create a new plugin, use the Flutter CLI command:

```bash
flutter create --org com.proton --template=plugin --platforms=ios,android,macos,web,linux,windows proton_plugin_name
```

## Adding New Platforms

To add a new platform to an existing plugin, use the following command from within the plugin directory:

```bash
flutter create --platforms=<platform_name> .
```

This will create a new plugin with the following features:

- Platform-specific implementations
- Example app
- Test directory
- Basic plugin structure
- Platform interface

## Development Guidelines

1. Follow Flutter's plugin development best practices
2. Maintain comprehensive documentation
3. Include example implementations
4. Write unit tests for core functionality
5. Keep dependencies up to date
6. Follow semantic versioning for releases
