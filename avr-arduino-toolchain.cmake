# AVR/Arduino CMake toolchain
#
# adds the toolchain and Arduino IDE libs
#
# @author Matthias L. Jugel <leo@ubirch.com>
#
# == LICENSE ==
# Copyright 2015 ubirch GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

cmake_minimum_required(VERSION 3.0)

# find compiler and toolchain programs
find_program(AVRCPP avr-g++)
find_program(AVRC avr-gcc)
find_program(AVRSTRIP avr-strip)
find_program(OBJCOPY avr-objcopy)
find_program(OBJDUMP avr-objdump)
find_program(AVRSIZE avr-size)
find_program(AVRDUDE avrdude)
find_program(SCREEN screen)

# toolchain settings
set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_CXX_COMPILER ${AVRCPP})
set(CMAKE_C_COMPILER ${AVRC})
set(CMAKE_ASM_COMPILER ${AVRC})

# Important project paths
set(BASE_PATH "${${PROJECT_NAME}_SOURCE_DIR}")
set(SRC_PATH "${BASE_PATH}/src")
set(LIB_PATH "${BASE_PATH}/lib")

# necessary settings for the chip we use
set(MCU atmega328p CACHE STRING "CPU type")
set(F_CPU 16000000 CACHE INTEGER "CPU frequency")
set(BAUD 115200 CACHE INTEGER "UART baud rate")
set(PROGRAMMER arduino CACHE STRING "programmer type")
set(MONITOR ${SCREEN} CACHE STRING "serial monitor program")
set(MONITOR_ARGS ${SERIAL_DEV} ${BAUD} CACHE STRING "serial monitor arguments")

set(COMPILER_FLAGS "-Os -Wall -Wno-unknown-pragmas -Wextra -MMD -mmcu=${MCU} -DF_CPU=${F_CPU}" CACHE STRING "")
set(CMAKE_C_FLAGS "${COMPILER_FLAGS} -std=gnu99 -mcall-prologues -ffunction-sections -fdata-sections" CACHE STRING "")
set(CMAKE_CXX_FLAGS "${COMPILER_FLAGS} -fno-exceptions -ffunction-sections -fdata-sections -fno-threadsafe-statics" CACHE STRING "")
set(CMAKE_ASM_FLAGS "-x assembler-with-cpp ${COMPILER_FLAGS} " CACHE STRING "")
set(CMAKE_EXE_LINKER_FLAGS "-Wl,--gc-sections ${EXTRA_LIBS}" CACHE STRING "")

# some definitions that are common
add_definitions(-DMCU=${MCU})
add_definitions(-DF_CPU=${F_CPU})
add_definitions(-DBAUD=${BAUD})

# we need a little function to add multiple targets
function(add_executable_avr NAME)
    add_executable(${NAME} ${ARGN})
    set_target_properties(${NAME} PROPERTIES OUTPUT_NAME "${NAME}.elf")
    set_directory_properties(PROPERTIES ADDITIONAL_MAKE_CLEAN_FILES "${NAME}.hex;${NAME}.eep;${NAME}.lst")

    # generate the .hex file
    add_custom_command(
            OUTPUT ${NAME}.hex
            COMMAND ${AVRSTRIP} "${NAME}.elf"
            COMMAND ${OBJCOPY} -O ihex -j .eeprom --set-section-flags=.eeprom=alloc,load --no-change-warnings --change-section-lma .eeprom=0 "${NAME}.elf" "${NAME}.eep"
            COMMAND ${OBJCOPY} -O ihex -R .eeprom "${NAME}.elf" "${NAME}.hex"
            COMMAND ${AVRSIZE} --mcu=${MCU} -C --format=avr "${NAME}.elf"
            DEPENDS ${NAME})
    add_custom_target(${NAME}-strip ALL DEPENDS ${NAME}.hex)

    # add a reset command using avrdude (only if it does not yet exist)
    if (NOT TARGET avr-reset)
        add_custom_target(avr-reset COMMAND ${AVRDUDE} -c${PROGRAMMER} -p${MCU})
    endif ()

    if (PROGRAMMER STREQUAL "usbasp")
        set(AVRDUDE_ARGS -c${PROGRAMMER} -p${MCU} -Pusb)
    else()
        set(AVRDUDE_ARGS -c${PROGRAMMER} -p${MCU} -P${SERIAL_DEV} -b${BAUD})
    endif ()

    # flash the produces binary
    add_custom_target(
            ${NAME}-flash
            COMMAND ${AVRDUDE} ${AVRDUDE_ARGS} -U flash:w:${NAME}.hex
            DEPENDS ${NAME}.hex)
    add_custom_target(
            ${NAME}-monitor
            COMMAND ${MONITOR} ${MONITOR_ARGS})
endfunction(add_executable_avr)

# add all the libraries as possible library dependencies
function(add_libraries LIB_PATH)
    set(PROJECT_LIBS)
    file(GLOB LIB_DIRS "${LIB_PATH}/*/CMakeLists.txt")
    foreach (cmakedir ${LIB_DIRS})
        get_filename_component(subdir ${cmakedir} PATH)
        if (IS_DIRECTORY ${subdir})
            get_filename_component(target ${subdir} NAME)
            message(STATUS "Adding ubirch avr library: ${target}")
            add_subdirectory(${subdir})
        endif ()
    endforeach ()
endfunction()

# add targets automatically from the src directory
function(add_sources SRC_PATH)
    file(GLOB SRC_DIRS "${SRC_PATH}/*/CMakeLists.txt")
    foreach (cmakedir ${SRC_DIRS})
        get_filename_component(subdir ${cmakedir} PATH)
        if (IS_DIRECTORY ${subdir})
            get_filename_component(target ${subdir} NAME)
            message(STATUS "Found ubirch avr target: ${target}")
            add_subdirectory(${subdir})
        endif ()
    endforeach ()
endfunction()


# ====================================================================================================================
# ARDUINO SKETCH FUNCTIONALITY
# ====================================================================================================================
# set the arduino sdk path from an environment variable if given
if (DEFINED ENV{ARDUINO_SDK_PATH})
    set(ARDUINO_SDK_PATH "$ENV{ARDUINO_SDK_PATH}" CACHE PATH "Arduino SDK Path" FORCE)
endif ()

set(ARDUINO_CORE_LIBS "" CACHE INTERNAL "arduino core libraries")
function(setup_arduino_core)
    if (DEFINED ARDUINO_SDK_PATH AND IS_DIRECTORY ${ARDUINO_SDK_PATH} AND NOT(TARGET arduino-core))
        # set the paths
        set(ARDUINO_CORES_PATH ${ARDUINO_SDK_PATH}/hardware/arduino/avr/cores/arduino CACHE STRING "")
        set(ARDUINO_VARIANTS_PATH ${ARDUINO_SDK_PATH}/hardware/arduino/avr/variants/standard CACHE STRING "")
        set(ARDUINO_LIBRARIES_PATH ${ARDUINO_SDK_PATH}/hardware/arduino/avr/libraries CACHE STRING "")

        # find arduino-core sources
        file(GLOB_RECURSE CORE_SOURCES ${ARDUINO_CORES_PATH}/*.S ${ARDUINO_CORES_PATH}/*.c ${ARDUINO_CORES_PATH}/*.cpp)

        set(ARDUINO_CORE_SRCS ${CORE_SOURCES} CACHE STRING "Arduino core library sources")

        # setup the main arduino core target
        add_library(arduino-core ${ARDUINO_CORE_SRCS})
        target_include_directories(arduino-core PUBLIC ${ARDUINO_CORES_PATH})
        target_include_directories(arduino-core PUBLIC ${ARDUINO_VARIANTS_PATH})

        # configure all the additional libraries in the core
        file(GLOB CORE_DIRS ${ARDUINO_LIBRARIES_PATH}/*)
        foreach (libdir ${CORE_DIRS})
            get_filename_component(libname ${libdir} NAME)
            if (IS_DIRECTORY ${libdir})
                file(GLOB_RECURSE sources ${libdir}/*.cpp ${libdir}/*.S ${libdir}/*.c)
                string(REGEX REPLACE "examples/.*" "" sources "${sources}")
                if (sources)
                    if (NOT TARGET ${libname})
                        message(STATUS "Adding Arduino Core library: ${libname}")
                        add_library(${libname} ${sources})
                    endif ()
                    target_link_libraries(${libname} arduino-core)
                    foreach (src ${sources})
                        get_filename_component(dir ${src} PATH)
                        target_include_directories(${libname} PUBLIC ${dir})
                    endforeach ()
                    list(APPEND ARDUINO_CORE_LIBS ${libname})
                    set(ARDUINO_CORE_LIBS ${ARDUINO_CORE_LIBS} CACHE INTERNAL "arduino core libraries")
                else()
                    include_directories(SYSTEM ${libdir})
                endif ()
            endif ()
        endforeach ()

        # add some of the default definitions (TODO: identify from Arduino IDE)
        add_definitions(-DARDUINO=10605)
        add_definitions(-DARDUINO_AVR_UNO)
        add_definitions(-DARDUINO_ARCH_AVR)
    endif ()
endfunction()

function(add_sketches SKETCHES_PATH)
    setup_arduino_core()
    if (TARGET arduino-core)
        # finally add all the sketches
        file(GLOB SRC_DIRS "${SKETCHES_PATH}/*/CMakeLists.txt")
        foreach (cmakedir ${SRC_DIRS})
            get_filename_component(subdir ${cmakedir} PATH)
            if (IS_DIRECTORY ${subdir})
                get_filename_component(target ${subdir} NAME)
                message(STATUS "Found Arduino sketch: ${target}")
                add_subdirectory(${subdir})
            endif ()
        endforeach ()
    else()
        message(WARNING "No Arduino SDK found at '${ARDUINO_SDK_PATH}', can't compile sketches!")
    endif ()
endfunction()

set(SKETCH_LIBS "" CACHE INTERNAL "arduino sketch libraries")
# add a sketch dependency by giving the target and a git url
function(target_sketch_library TARGET NAME URL)
    setup_arduino_core()
    if (TARGET arduino-core AND NOT TARGET ${NAME})
        # try to install dependent libraries
        find_package(Git)
        if (GIT_FOUND)
            # clone dependency into libraries
            get_filename_component(MYLIBS "${CMAKE_CURRENT_SOURCE_DIR}/../libraries" REALPATH)
            if (NOT EXISTS ${MYLIBS})
                message(STATUS "creating library directory: ${MYLIBS}")
                file(MAKE_DIRECTORY ${MYLIBS})
            endif ()
            if (NOT EXISTS ${MYLIBS}/${NAME})
                message(STATUS "Installing ${NAME} (${URL})")
                execute_process(
                        COMMAND ${GIT_EXECUTABLE} clone "${URL}" "${NAME}"
                        WORKING_DIRECTORY ${MYLIBS})
            endif ()

            # now add a library target
            file(GLOB_RECURSE libsources FOLLOW_SYMLINKS ${MYLIBS}/${NAME}/*.S ${MYLIBS}/${NAME}/*.c ${MYLIBS}/${NAME}/*.cpp)
            # go through list of sources and remove the examples
            foreach (file ${libsources})
                STRING(REGEX MATCH "/examples/" example ${file})
                if (NOT example)
                    list(APPEND sources ${file})
                endif ()
            endforeach ()
            if (sources)
                message(STATUS "Adding external library: ${NAME}")
                add_library(${NAME} ${sources})
                target_link_libraries(${NAME} ${ARDUINO_CORE_LIBS} ${SKETCH_LIBS})
                list(APPEND SKETCH_LIBS ${NAME})
                set(SKETCH_LIBS ${SKETCH_LIBS} CACHE INTERNAL "arduino sketch libraries")
                foreach (src ${sources})
                    get_filename_component(dir ${src} PATH)
                    list(APPEND includes ${dir})
                endforeach ()
                list(REMOVE_DUPLICATES includes)
                target_include_directories(${NAME} PUBLIC ${includes})
            else()
                message(FATAL_ERROR "Could not find sources in library ${NAME}!")
            endif ()
        else()
            message(FATAL_ERROR "Missing git, please install and try again!")
        endif ()
    endif ()
    target_link_libraries(${TARGET} ${NAME})
endfunction(target_sketch_library)
