Monitors tested:

- 34" Works only at reduced resolution (over displayport)
- 27" **P2715Q**: Working at 4K (3840x2160) resolution on Ubuntu 15.10 over Displayport
- 24" (1920x1080)

-----------

## Logs / performance notes



- **Native display** `glxgears` on native screen gets about 60 FPS (at full resolution, 3200 x 2880)
- **24" HD Dell** : `glxgears` running on 24" Dell at 1920x1080 60Hz over DisplayPort cable gets about 60 FPS. `300 frames in 5.0 seconds = 59.991 FPS`
  - Same whether or not DP 1.2 has been enabled on monitor menu. 
  - Same whether or not native screen also on.  
- **27" 4K Dell**: 3840x2160 over displayport connection `glxgears` reports 60 FPS (with native screen off).
  - With both native monitor and 27" on, the speed reported is higher, ~120 FPS, but actually looks less smooth
  - the 27", 4K Dell doesn't have the option in the menu to enable displayport 1.2


