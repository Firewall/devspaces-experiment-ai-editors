# Upstream software

The [MIT license](LICENSE) covers this repository's integration code. Software downloaded or built by the Containerfiles keeps its own license, including its dependencies and base image packages.

| Component | Source and terms |
| --- | --- |
| T3 Code | [Source](https://github.com/pingdotgg/t3code), [MIT license](https://github.com/pingdotgg/t3code/blob/main/LICENSE) |
| OpenChamber | [Source](https://github.com/openchamber/openchamber), [MIT license](https://github.com/openchamber/openchamber/blob/main/LICENSE) |
| Orca | [Source at v1.4.219](https://github.com/stablyai/orca/tree/v1.4.219), [MIT license](third_party/orca-LICENSE) |
| OpenCode | [Source](https://github.com/anomalyco/opencode), [license](https://github.com/anomalyco/opencode/blob/dev/LICENSE) |
| VS Code | [Microsoft product license](https://code.visualstudio.com/license), [server terms](https://code.visualstudio.com/license/server) |
| bubblewrap | [Source and license](https://github.com/containers/bubblewrap) |

`orca/web-client.patch` modifies Orca. Its upstream copyright notice is preserved in [third_party/orca-LICENSE](third_party/orca-LICENSE). The Orca image and injector also retain the upstream `LICENSE` alongside the runtime.

The VS Code Agent Host recipe downloads the official Microsoft CLI, which can download further runtime components. Microsoft's product and server terms differ from the MIT license on the VS Code source repository. Review those terms before distributing an image containing Microsoft binaries or offering a hosted service.

These links identify the main components. They are not a complete inventory of the packages inside a built image. Preserve the license files and notices shipped with upstream packages when redistributing an image.
