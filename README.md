iosinmemoryrecord
=================

Example of recording and playing back audio data on iOS using an IO Audio Unit.

Overview
--------
This is a reference project which is the result of a few weeks of learing about the audio recording capabilities of the iOS platform. 

The project illustrates the following:
  * simplistic use of the AudioUnit API, in particular the remote I/O unit
  * interaction between Objective-C methods and C functions with ARC enabled
  * a basic technique to solve the problem of displaying real-time information on the user interface
  * setup and use of in-memory data buffers tailored towards capturing live audio data from the device
