# Compile the component files and this entry point into one .mrb. See README.
require "cyw43"
require "cyw43/ap"
require "machine"
require "socket"

PicoTimerApp.new.run
