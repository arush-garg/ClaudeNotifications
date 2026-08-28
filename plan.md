The goal is to allow Claude (or any MCP capable agent) to send physical notifications to users via an OLED display and buzzer. This will prevent the frustration of leaving claude to work, only to come back and realize it needs input on something.

What I need to build
1. HardwareBridge: Uses usb serial to communicate with the OLED display and buzzer. 
2. MCP server: Build off standard MCP server to expose an API for sending notifications to the HardwareBridge.

There should also be utils/ that takes config.json and compiles it into Constants.h for HardwareBridge if that's easier than JSON reading and parsing on the microcontroller. Install instructions should also suggest installing arduino cli

MCP server should inject instructions to flash code to the microcontroller when interacting for the first time


Behavior:
1. Tool that claude can call to send a notification to the HardwareBridge. It beeps 3 times and displays a message on the OLED screen for 1 minute (both the beep count and display time should be configurable in config.json).
2. Pre tool hook for clarify (and the ask for permission pop up if possible)
    FOr now I'll stick to just Claude and maybe in the future others can implement the hooks for other agents.