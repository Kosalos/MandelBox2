import Foundation
import UIKit

enum RecordState { case idle,recording,playing }
let numStepsMin:Int = 25
let numStepsMax:Int = 1600

var recordStruct = RecordStruct()

class Record {
    var state:RecordState = .idle
    var pIndex = Int()
    var cameraDelta = float3()
    var focusDelta = float3()
    var parallaxDelta = Float()
    var numSteps:Int = numStepsMin
    var step = Int()

    func determineDeltas() {
        if recordStruct.count > 1 {
            let entry = getRecordStructEntry(Int32(pIndex))
            let nextEntry = getRecordStructEntry(Int32(pIndex+1))
            let fSteps = Float(numSteps)
            cameraDelta = (nextEntry.camera - entry.camera) / fSteps
            focusDelta = (nextEntry.focus - entry.focus) / fSteps
            parallaxDelta = (nextEntry.parallax - entry.parallax) / fSteps
        }
    }
    
    func loadEntry() {
        let entry = getRecordStructEntry(Int32(pIndex))
        control.camera = entry.camera
        control.focus = entry.focus
        control.parallax = entry.parallax
        aData = entry.aData
    }
    
    func playBack() {
        step += 1
        if step >= numSteps {
            pIndex += 1
            
            // -1 = play to last entry, then start again (don't animate from end to beginning, but jump directly)
            if pIndex >= recordStruct.count-1 {
                pIndex = 0
                loadEntry()
            }
            
            step = 0
            determineDeltas()
        }
        
        control.camera += cameraDelta
        control.focus += focusDelta
        control.parallax += parallaxDelta
     }
    
    func refreshDisplay() { vc.wg.setNeedsDisplay() }
    
    func recordPressed() {
        if state != .recording {
            state = .recording
            recordStruct.count = 0
            saveControlMemory()
        }

        saveRecordStructEntry()
        refreshDisplay()
    }
    
    func playbackPressed() {
        if state == .playing {
            state = .idle
            loadEntry()
        }
        else {
            if recordStruct.count > 1 {
                state = .playing
                pIndex = 0
                step = 0
                determineDeltas()
                
                restoreControlMemory()
                vc.controlJustLoaded()
            }
        }
        
        refreshDisplay()
    }
    
    func playSpeedPressed() {
        numSteps *= 2
        if numSteps > numStepsMax { numSteps = numStepsMin }
        determineDeltas()
        refreshDisplay()
    }
    
    func getCount() -> Int { return Int(recordStruct.count) }
    
    func reset() {
        state = .idle
        recordStruct.count = 0
        refreshDisplay()
    }
}
