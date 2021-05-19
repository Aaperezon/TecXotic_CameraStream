#!/usr/bin/env bash
PATH=/opt/someApp/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LD_LIBRARY_PATH=/usr/local/lib/

if [ -z "$1" ]; then
    WIDTH=$(cat ~/Video/vidformat.param | xargs | cut -f1 -d" ")
    HEIGHT=$(cat ~/Video/vidformat.param | xargs | cut -f2 -d" ")
    FRAMERATE=$(cat ~/Video/vidformat.param | xargs | cut -f3 -d" ")
    DEVICE=$(cat ~/Video/vidformat.param | xargs | cut -f7 -d" ")
else
    WIDTH=$1
    HEIGHT=$2
    FRAMERATE=$3
    DEVICE=$4
fi

echo "start video with width $WIDTH height $HEIGHT framerate $FRAMERATE device $DEVICE"

# Load Pi camera v4l2 driver
if ! lsmod | grep -q bcm2835_v4l2; then
    echo "loading bcm2835 v4l2 module"
    sudo modprobe bcm2835-v4l2
fi

# check if this device is H264 capable before streaming
# It would be better not to specify framerate, but there is an issue with RPi camera v4l2 driver, it will cause kernel error to use default framerate (90 fps)
gst-launch-1.0 -v v4l2src device=$DEVICE do-timestamp=true num-buffers=1 ! image/jpeg ! rtpjpegpay ! fakesink

# if it is not, check all available devices, and use the first h264 capable one instead
if [ $? != 0 ]; then
    echo "specified device $DEVICE failed"
    for DEVICE in $(ls /dev/video*); do
        echo "attempting to start $DEVICE"
        gst-launch-1.0 -v v4l2src device=$DEVICE do-timestamp=true num-buffers=1 ! image/jpeg ! rtpjpegpay ! fakesink
        if [ $? == 0 ]; then
            echo "Success!"
            break
        fi
    done
fi

# load gstreamer options
gstOptions1="$(sed '8q;d' ~/gstreamer2.param)"

# make sure framesize and framerate are supported

# workaround to make sure we don't attempt 1080p@90fps on pi camera
v4l2-ctl --device $DEVICE --set-parm $FRAMERATE

echo "attempting device $DEVICE with width $WIDTH height $HEIGHT framerate $FRAMERATE options $gstOptions1"
gst-launch-1.0 -v v4l2src device=$DEVICE do-timestamp=true num-buffers=1 ! image/jpeg,width=$WIDTH,height=$HEIGHT,videorate=$FRAMERATE ! rtpjpegpay config-interval=10 pt=96 ! fakesink

if [ $? != 0 ]; then
    echo "Device is not capable of specified format, using device current settings instead"
    bash -c "export LD_LIBRARY_PATH=/usr/local/lib/ && gst-launch-1.0 -v v4l2src device=$DEVICE do-timestamp=true ! video/x-h264 $gstOptions1"
else
    echo "starting device $DEVICE with width $WIDTH height $HEIGHT framerate $FRAMERATE options $gstOptions1"
    bash -c "export LD_LIBRARY_PATH=/usr/local/lib/ && gst-launch-1.0 -v v4l2src device=$DEVICE do-timestamp=true ! video/x-h264, width=$WIDTH, height=$HEIGHT, framerate=$FRAMERATE/1 $gstOptions1"
    # if we make it this far, it means the gst pipeline failed, so load the backup settings
    cp ~/Video/vidformat.param.bak ~/Video/vidformat.param && rm ~/Video/vidformat.param.bak
fi

