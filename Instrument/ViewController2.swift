//
//  ViewController.swift
//  Instrument


import UIKit
import AVFoundation
import AudioUnit

// AVAudioEngine
var audioEngine : AVAudioEngine!
// one player node
var player : AVAudioPlayerNode!

// one node to add reverb
var reverb : AVAudioUnitReverb!

// frequency range
let defaultFreq = 440.0 // A4 = 440
let minimumFreq = 220.0 // A3, one octave below, half the amount
let maximumFreq = 880.0 // A5, one octave above, twice the amount

// gain range
let minimumGain = 0.1
let maximumGain = 0.6

// set this to true to restrict to a scale
let restrictToScale = false

// we use sampleRate a lot
var sampleRate : Double!

// the circle under the finger
var fingerGraphic : UIView!

class ViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // create the graphic shown under the finger
        self.createTouchPointGraphic()
        
        audioEngine = AVAudioEngine()
        player = AVAudioPlayerNode()
        
        // we need the sample rate (almost certainly 44100) to calculate our sine waves
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
    
    // MARK: handling touches
    
    func calculatePitchAndVolume(_ touch: UITouch) -> (newPitch : Double, newVolume: Double) {
        
        let fingerPosition = touch.location(in: self.view)
        
        let width = self.view.frame.width
        let height = self.view.frame.height
        
        // this code maps a finger position to a frequency range
        let xRatio = fingerPosition.x / width
        let frequencyRange = maximumFreq - minimumFreq
        let positionInWidth = frequencyRange * Double(xRatio) + minimumFreq
        
        // we want a curve, or the pitches on left will be closer together than the pitches on the right
        let logMin = log(minimumFreq)
        let logMax = log(maximumFreq)
        let freqScale = (logMax - logMin) / (frequencyRange)
        let newFrequency = exp(logMin + (freqScale * (positionInWidth - minimumFreq)))
        
        // now, do the same on the Y axis to alter the volume (simple range this time)
        let yRatio = fingerPosition.y / height
        let gainRange = maximumGain - minimumGain
        let newGain = maximumGain - gainRange * Double(yRatio)
        
        return (newFrequency, newGain)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        
        let touch = touches.first as UITouch!
        
        // make the graphic visible
        fingerGraphic.center  = (touch?.location(in: self.view))!
        fingerGraphic.isHidden = false
        
        // start a tone
        let pitchAndVolume = calculatePitchAndVolume(touch!)
        let audioChunk = generateSineWave(pitchAndVolume.newPitch, gain:pitchAndVolume.newVolume)
        
        // now start playing (and looping) the new audio segment
        player.scheduleBuffer(audioChunk, at: nil, options: .loops, completionHandler: nil)
        
        // start the player!
        player.play()
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent!) {
        let touch = touches.first as UITouch!
        
        // change position of graphic
        fingerGraphic.center  = (touch?.location(in: self.view))!
        
        let pitchAndVolume = calculatePitchAndVolume(touch!)
        let newAudioChunk = generateSineWave(pitchAndVolume.newPitch, gain:pitchAndVolume.newVolume)
        
        // interrupt the existing playing audio
        player.scheduleBuffer(newAudioChunk, at: nil, options: .interruptsAtLoop, completionHandler:nil)
        // loop the new audio
        player.scheduleBuffer(newAudioChunk, at: nil, options: .loops, completionHandler: nil)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent!) {
        
        // get final position
        let touch = touches.first as UITouch!
        let result = calculatePitchAndVolume(touch!)
        
        // hide graphic again
        fingerGraphic.isHidden = true
        
        // now, FADE the sound out.
        let fadingAudioBuffer = generateSineFade(result.newPitch, gain:result.newVolume)
        
        // interrupt the existing playing audio
        player.scheduleBuffer(fadingAudioBuffer, at: nil, options: .interruptsAtLoop, completionHandler: {
            player.stop()
        })
    }
    
    // MARK: Sound creation methods
    
    func generateSineWave(_ frequency : Double, gain: Double) -> AVAudioPCMBuffer {
        var frequency = frequency
        
        // restrict to play specific notes
        if restrictToScale {
            frequency = enforceScale(frequency)
        }
        
        // how many samples needed for one complete wave?
        let period = Int( sampleRate / frequency )
        
        let newbuffer = AVAudioPCMBuffer(pcmFormat: player.outputFormat(forBus: 0), frameCapacity: UInt32(period))
        newbuffer.frameLength = UInt32(period)
        
        for i in 0..<period {
            let value = sin(frequency * Double(i) * (M_PI * 2) / sampleRate)
            newbuffer.floatChannelData?[0][i] = Float(value * gain)
            newbuffer.floatChannelData?[1][i] = Float(value * gain)
        }
        return newbuffer
    }
    
    func generateSineFade(_ frequency : Double, gain: Double) -> AVAudioPCMBuffer {
        var frequency = frequency, gain = gain
        
        // restrict to play specific notes
        if restrictToScale {
            frequency = enforceScale(frequency)
        }
        
        // how many samples needed for one complete wave?
        let period = Int( sampleRate / frequency )
        
        let newbuffer = AVAudioPCMBuffer(pcmFormat: player.outputFormat(forBus: 0), frameCapacity: UInt32(period))
        newbuffer.frameLength = UInt32(period)
        
        let gainDelta = gain / Double(period)
        
        for i in 0..<period {
            // this is the difference! We reduce the gain to make it fade out
            gain -= gainDelta
            if gain < 0 { gain = 0.0 }
            let value = sin(frequency * Double(i) * (M_PI * 2) / sampleRate)
            newbuffer.floatChannelData?[0][i] = Float(value * gain)
            newbuffer.floatChannelData?[1][i] = Float(value * gain)
        }
        return newbuffer
    }
    
    func enforceScale(_ inputPitch : Double) ->  Double {
        
        // A minor scale
        //let scale = [ 220, 246.94, 261.63, 293.66, 329.63, 349.23, 392.00, 440.0, 493.88, 523.25, 587.33, 659.26, 698.46, 783.99, 880.0]
        
        // Japanese iwato scale
        let scale = [ 220, 233.08, 293.66, 311.125, 392, 440.0, 466.16, 587.33, 622.25, 739.99, 880.0]
        
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
}

