cmake_minimum_required(VERSION 3.16)
project(occt_sdk_consumer LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(OpenCASCADE CONFIG REQUIRED)

add_executable(occt_sdk_consumer main.cpp)
target_link_libraries(occt_sdk_consumer PRIVATE TKBO TKPrim TKTopAlgo TKDESTEP)
