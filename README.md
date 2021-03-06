                                           _
    /'\_/`\                               ( )
    |     | _   _  _ __  _   _   ___ ___  | |     _   _
    | (_) |( ) ( )( '__)( ) ( )/' _ ` _ `\| |  _ ( ) ( )(`\/')
    | | | || (_) || |   | (_) || ( ) ( ) || |_( )| (_) | >  <
    (_) (_)`\___/'(_)   `\___/'(_) (_) (_)(____/'`\___/'(_/\_)


MurumLux (latin: "Wall of Light") is a demo piece for Microchip's ChipKIT and Sabrewing development systems.

----------------------
####What is in this repository:
**./3DModels**: Blender models of the physical pieces that comprise a finished unit.

**./image_converter**: Logos that found their way into the build.

**./doc**:  Documentation related to this project.

**./lib**:  Libraries that are needed by this project.

**./src**:  Original (unless otherwise specified) source code.

image_converter

----------------------
####Building the device firmware under MPIDE.

You will need to follw the instructions [at this link](http://www.joshianlindsay.com/index.php?id=147) to fix Arduino fail (if
you haven't done something equivalent already). Then, you will need to move (or
link) the directories in ./lib/ to your Arduino library directory.

There are two PDE files in this repo. One for the LED panel, and one for the
e-field box. You might need to break them out into separate sketch folders prior
to building.

The LED panel is being run on a Digilent WiFire board (chipKIT). The e-field box
is using a Fubarino Mini (also a chipKIT part). By selecting those boards in MPIDE,
and following the instructions above, you ought to be able to build both projects.


----------------------
####License
GPL v2

----------------------
####Cred:
The ASCII art in this file was generated by [this most-excellent tool](http://patorjk.com/software/taag).

Some of the hardware drivers are adaptions from Adafruit code. This is noted in each specific class so derived.

The DMA implementation was copy-pasta'd from Keith Vogel's LMBling library for NeoPixels.

The GoL implementation was an adaption of [code by user creativename](http://runnable.com/UwQvQY99xW5AAAAQ/john-conway-s-game-of-life-for-c%2B%2B-nested-for-loops-and-2-dimensional-arrays) at runnable.com


The MGC3130 driver is an adaption (re-write) of the Hover arduino demo code.
