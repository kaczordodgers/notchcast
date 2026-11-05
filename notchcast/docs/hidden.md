# Hidden fork features

Unwired fork features start off and are absent from Settings, search and the launcher; see `NotchcastFeature.unwired` in `Tinycast/Features/Notchcast/Core/NotchcastFeature.swift`. Settings backup restore writes their switches as false, so importing a backup cannot enable them. Direct preference changes remain available to harnesses testing the kept code.

Agent Answers (`agentAnswer`) was already hidden by #209 because no reply transport exists; its code stays in place.
