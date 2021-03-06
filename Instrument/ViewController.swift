//
//  ViewController.swift
//  Instrument
//
//  Created by Hamzah Mugharbil on 8/10/17.
//  Copyright © 2017 Hamzah Mugharbil. All rights reserved.
//

import UIKit
import AVFoundation
import AudioUnit

// AVAudio Engine
var audioEngine: AVAudioEngine!
// one player node
var player: AVAudioPlayerNode!

// one node to add reverb
var reverb: AVAudioUnitReverb!

// frequency range
let defaultFreq = 440.0 // A4 = 440
let maximumFreq = 880.0 // A5, one octave above, twice the amount
let minimumFreq = 220.0 // A3, one octave below, half the amount

// gain range
let minimumGain = 0.1
let maximumGain = 1.0

// set this to be true to restrict to a scale
let restrictToScale = false

// we use sampleRate a lot
var sampleRate: Double!

// the circle under the finger
var fingerGraphic: UIView!


class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // create the graphic shown under the finger
        self.createTouchPointGraphic()
        
        audioEngine = AVAudioEngine()
        player = AVAudioPlayerNode()
        
        // sample rate to calculate the sine wave (44,100)
        sampleRate = player.outputFormat(forBus: 0).sampleRate
        
        reverb = AVAudioUnitReverb()
        reverb.loadFactoryPreset(AVAudioUnitReverbPreset.largeHall)
        // from 0 (dry) to 100 (all reverb)
        reverb.wetDryMix = 70
        
        // setup audio engine
        audioEngine.attach(player)
        audioEngine.attach(reverb)
        
        // connect the nodes
        audioEngine.connect(player, to: reverb, format: nil)
        audioEngine.connect(reverb, to: audioEngine.outputNode, format: nil)
        
        // start the engine
        do {
            try audioEngine.start()
            
        } catch {
            print("\(error)")
        }
        
    }

    func createTouchPointGraphic() {
        fingerGraphic = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        fingerGraphic.backgroundColor = UIColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1.0)
        fingerGraphic.layer.cornerRadius = 22
        fingerGraphic.isHidden = true
        self.view.addSubview(fingerGraphic)
    }
    
    // MARK: - handling touches
    func calculatePitchAndVolume(_ touch: UITouch) -> (newPitch: Double, newVolume: Double) {
        
        let fingerPosition = touch.location(in: self.view)
        
        let width = self.view.frame.width
        let height = self.view.frame.height
        
        // this code maps a finger position to a frequency range (x-axis)
        let xRatio = fingerPosition.x/width
        let frequencyRange = maximumFreq - minimumFreq
        let positionInWidth = frequencyRange * Double(xRatio) + minimumFreq
        
        // we want a curve, or the pitches on the left will be closer together than the pitches on the right
        let logMin = log(minimumFreq)
        let logMax = log(maximumFreq)
        let freqScale = (logMax - logMin)/(frequencyRange)
        let newFrequency = exp(logMin + (freqScale * (positionInWidth - minimumFreq)))
        
        // same to alter the volume (y-axis)
        let yRatio = fingerPosition.y/height
        let gainRange = maximumGain - minimumGain
        let newGain = maximumGain - gainRange * Double(yRatio)
        
        return(newFrequency, newGain)
        
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        
        let touch = touches.first as UITouch!
        
        // make the graphic visible
        fingerGraphic.center  = (touch?.location(in: self.view))!
        fingerGraphic.isHidden = false
        
        // start a tone
        let pitchAndVolume = calculatePitchAndVolume(touch!)
        let audioChunk = generateSineWave(frequency: pitchAndVolume.newPitch, gain:pitchAndVolume.newVolume)
        
        // now start playing (and looping) the new audio segment
        player.scheduleBuffer(audioChunk, at: nil, options: .loops, completionHandler: nil)
        
        // start the player!
        player.play()
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        
        let touch = touches.first as UITouch!
        
        // change position of graphic
        fingerGraphic.center = (touch?.location(in: self.view))!
        
        let pitchAndVolume = calculatePitchAndVolume(touch!)
        let newAudioChunk = generateSineWave(frequency: pitchAndVolume.newPitch, gain: pitchAndVolume.newVolume)
        
        // interrupt the existing playing audio
        player.scheduleBuffer(newAudioChunk, at: nil, options: .interruptsAtLoop, completionHandler: nil)
        // loop the new audio
        player.scheduleBuffer(newAudioChunk, at: nil, options: .loops, completionHandler: nil)
        
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        
        // get final position
        let touch = touches.first as UITouch!
        let result = calculatePitchAndVolume(touch!)
        
        // hide graphic again
        fingerGraphic.isHidden = true
        
        // fade the sound out
        let fadingAudioBuffer = generateSineFade(frequency: result.newPitch, gain: result.newVolume)
        
        // interrupt the existing playing audio
        player.scheduleBuffer(fadingAudioBuffer, at: nil, options: .interruptsAtLoop, completionHandler: {
            player.stop()
        })
        
    }
    
    // MARK: sound creation methods
    
    func  generateSineWave(frequency: Double, gain: Double) -> AVAudioPCMBuffer {
        
        // restrict to play specific notes
        var frequency = frequency
        if restrictToScale {
            frequency = enforceScale(inputPitch: frequency)
        }
        
        // how many samples needed for one complete wave?
        let period = Int(sampleRate/frequency)
        
        let newBuffer = AVAudioPCMBuffer(pcmFormat: player.outputFormat(forBus: 0), frameCapacity: UInt32(period))
        newBuffer?.frameLength = UInt32(period)
        
        for i in 0..<period {
            let value = sin(frequency*Double(i)*(M_PI * 2)/sampleRate)
            newBuffer?.floatChannelData?[0][i] = Float(value * gain)
            newBuffer?.floatChannelData?[1][i] = Float(value * gain)
        }
        
        return newBuffer!
       
    }
    
    func generateSineFade(frequency: Double, gain: Double) -> AVAudioPCMBuffer {
        
        // restrict to play specific notes
        var frequency = frequency, gain = gain
        if restrictToScale {
            frequency = enforceScale(inputPitch: frequency)
        }
        
        // how many samples needed for one complete wave?
        let period = Int(sampleRate/frequency)
        
        let newBuffer = AVAudioPCMBuffer(pcmFormat: player.outputFormat(forBus: 0), frameCapacity: UInt32(period))
        newBuffer?.frameLength = UInt32(period)
        
        
        let gainDelta = gain/Double(period)
        
        
        for i in 0..<period {
            // same as sign wave, instead we reduce to make it fade
            gain -= gainDelta
            if gain < 0 { gain = 0.0 }
            let value = sin(frequency*Double(i)*(M_PI * 2)/sampleRate)
            newBuffer?.floatChannelData?[0][i] = Float(value * gain)
            newBuffer?.floatChannelData?[1][i] = Float(value * gain)
        }
        
        return newBuffer!
        
    }
    
    func enforceScale(inputPitch: Double) -> Double {
        
        // A minor scale
        //let scale = [220, 246.94, 261.63, 293.66, 329.63, 349.23, 392.00, 440.0, 493.88, 523.25, 587.33, 659.26, 698.46, 738.99, 880.0]
        
        // Japanese iwato scale
        let scale = [220, 233.08, 293.66, 311.125, 392, 440.0, 466.16, 587.33, 622.25, 739.99, 880.0]
        
        var closestPitch = scale.first!
        var maxDifference = abs(scale.first! - inputPitch)
        
        for currentPitch in scale {
            let difference = abs(currentPitch - inputPitch)
            if difference < maxDifference {
                maxDifference = difference
                closestPitch = currentPitch
            }
        }
        
        return closestPitch
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

