# AVR/Arduino CMake Toolchain

A toolchain for compiling avr code and Arduino Sketches using CMake and CLion.

See [ubirch-avr](https://github.com/ubirch/ubirch-avr) for an example where all variants are used.

### Prerequisits

Install the toolchain:

For MacOS X the simplest way to get the toolchain is [homebew](http://brew.sh/):

```
brew tap larsimmisch/avr
brew install avr-binutils avr-gcc avr-libc avrdude
brew install cmake
```

If you want to be able to compile [Arduino](https://www.arduino.cc/) sketches you will also need
the [Arduino SDK](https://www.arduino.cc/en/Main/Software) and set the environment variable ARDUINO_SDK_PATH.

## Building

The toolchain creates some functions to add static libs, sources and sketches to the build process:

### static libraries

Create a directory where you have your libs (in separate sub directories). Just like in other CMake projects, each
library needs a ```CMakeLists.txt``` like the following:

```
# tell the build system what to build
add_library(example-lib example-lib.c)
# for libraries also add the directory to the include path
target_include_directories(example-lib PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
```

### avr targets

Create a directory where you store each of your targets in a separate subdirectory. Like the static libs, you will
need a ```CMakeLists.txt``` in each of the targets directories. This time, we need to call one of the functions from
the toolchain ```add_executable_avr()``` to declare the executable target:

```
# tell the build system what to build
add_executable_avr(example example.c)
# declare what dependencies this executable has
target_link_libraries(example example-lib)
```

### Arduino sketches

Sketchs should also be put each in their own directory. Just like libs and targets they will need a
```CMakeLists.txt``` each which declares the target and dependencies. The core library is calles ```arduino-core```.
Other core libs like ```SoftwareSerial``` and ```Wire``` are also available. Unlike the Arduino IDE you need to
declare each dependency.

If you use 3rd party libraries, like the [Adafruit FONA library](https://github.com/adafruit/Adafruit_FONA_Library),
just use the special function ```target_sketch_library()``` which takes the target, the name of the library and a
git repository URL. The toolchain automatically clones (downloads) the library and adds the dependency. You will
find the library then in a ```libraries``` directory next to your sketches.

```
# tell the buold system your sketch name and the sources
add_executable_avr(example-sketch example-sketch.cpp)

# we require a number of arduino libraries for this
# (they already depend on arduino-core, so we don't need it here)
# install these libraries and either copy them or create a link in the 'external' directory
target_link_libraries(example-sketch arduino-core SoftwareSerial)

# special external dependencies can be added like this and will be downloaded once (automatically)
# arguments: <target> <name> <git url>
target_sketch_library(example-sketch Adafruit_FONA_Library https://github.com/adafruit/Adafruit_FONA_Library)
```

## Make

Your project needs also to be declared. Edit the example and put it into the top directory.

1. Edit CMakeLists.txt and set PROG_TYPE and PROG_DEV to your flash programmer and device.
2. follow the following procedure:

```
mkdir build
cd build
cmake ..
make eliza-flash monitor
```

To flash a target use the directory name with added -flash (example-flash).

> Unless you make significant changes to the CMakeLists.txt you only need to run ```make``` in
> the build directory from now on.
