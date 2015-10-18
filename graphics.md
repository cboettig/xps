Monitors tested:

- 34" **U3415W** Working at full resolution (3440x1440), 60 FPS, over DP (DP1.2 diabled)
- 27" **P2715Q**: Working at full 4K (3840x2160) resolution over DP. 
- 24" **U2414H** (1920x1080) Working at full resolution over DP, even with DP1.2 enabled.

-----------

## Logs / performance notes



- **Native display** `glxgears` on native screen gets about 60 FPS (at full resolution, 3200 x 2880)

- **U2414H** (24" Ultrasharp): `glxgears` running on 24" Dell at 1920x1080 60Hz over DisplayPort cable gets about 60 FPS. `300 frames in 5.0 seconds = 59.991 FPS`
  - Same whether or not DP 1.2 has been enabled on monitor menu. 
  - Same whether or not native screen also on.  

- **P2715Q** (27" 4K): 3840x2160 over displayport connection `glxgears` reports 60 FPS (with native screen off).
  - With both native monitor and 27" on, the speed reported is higher, ~120 FPS, but actually looks less smooth
  - DisplayPort 1.2 in enabled by default according to [Dell Knowledgebase article](http://www.dell.com/support/article/us/en/19/SLN296015/EN) and [P2715Q User Guide](http://content.etilize.com/User-Manual/1029519841.pdf):
    - **MST Off: (DP1.2 mode for single monitor setup)** Default mode: 4k*2k 60Hz with MST function Disabled.
    - **MST Primary: (DP1.2 mode for daisy chain setup)** MST function enabled for primary monitor in Daisy Chain setup. Expected resolution is 4k*2k 30Hz with MST (DP out) enabled.
    - **MST Secondary: (DP1.1 for daisy chain and single display setup)** MST function disabled for secondary monitor in Daisy Chain setup Expected resolution is 4k*2k 30Hz with MST (DP out) disabled.

- **U3415W** (34" Ultrasharp curved) DP 1.2 was enabled by default.  Selecting the full (3440x1440) resolution resulted in a blank screen; monitor could only display at lower resolution.  Turning off DP 1.2 allowed the display at full resolution, with `glxgears` reporting 60 FPS (whether or not laptop's native display was also on.)


