import UIKit
import Metal
import simd

var control = Control()
var record = Record()
var vc:ViewController! = nil

class ViewController: UIViewController, WGDelegate {
    var cBuffer:MTLBuffer! = nil
    var outTextureL: MTLTexture!
    var outTextureR: MTLTexture!
    var pipeline1: MTLComputePipelineState!
    lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var commandQueue: MTLCommandQueue! = { return device.makeCommandQueue() }()
    var isStereo:Bool = false
    var isHighRes:Bool = false

    let threadGroupCount = MTLSizeMake(20,20, 1)
    var threadGroups = MTLSize()
    
    @IBOutlet var metalTextureViewL: MetalTextureView!
    @IBOutlet var metalTextureViewR: MetalTextureView!
    @IBOutlet var wg:WidgetGroup!
    @IBOutlet var cRotate: CRotate!
    @IBOutlet var cTranslate: CTranslate!
    @IBOutlet var cTranslateZ: CTranslateZ!
    @IBOutlet var parallax: Widget!

    override var prefersStatusBarHidden: Bool { return true }
    
    //MARK: -
    
    override func viewDidLoad() {
        super.viewDidLoad()
        vc = self
        setRecordPointer(&recordStruct,&control)
        cBuffer = device.makeBuffer(bytes: &control, length: MemoryLayout<Control>.stride, options: MTLResourceOptions.storageModeShared)
        
        do {
            let defaultLibrary:MTLLibrary! = device.makeDefaultLibrary()
            guard let kf1 = defaultLibrary.makeFunction(name: "mandelBoxShader")  else { fatalError() }
            pipeline1 = try device.makeComputePipelineState(function: kf1)
        } catch { fatalError("error creating pipelines") }
        
        wg.initialize()
        wg.delegate = self
        initializeWidgetGroup()
        layoutViews()
        
        let parallaxRange:Float = 0.008
        parallax.initSingle(&control.parallax,  -parallaxRange,+parallaxRange,0.0002, "Parallax")
        parallax.highlight(0)

        for w in [ cTranslate,cTranslateZ,cRotate,parallax ] as [Any] { view.bringSubview(toFront:w as! UIView) }

        let tap2 = UITapGestureRecognizer(target: self, action: #selector(self.tap2Gesture(_:)))
        tap2.numberOfTapsRequired = 2
        view.addGestureRecognizer(tap2)

        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(self.swipeWgGesture(gesture:)))
        swipeUp.direction = .up
        wg.addGestureRecognizer(swipeUp)
        
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(self.swipeWgGesture(gesture:)))
        swipeDown.direction = .down
        wg.addGestureRecognizer(swipeDown)
        
        reset()
        Timer.scheduledTimer(withTimeInterval:0.05, repeats:true) { timer in self.timerHandler() }
    }
    
    @objc func tap2Gesture(_ sender: UITapGestureRecognizer) {
        wg.isHidden = !wg.isHidden
        layoutViews()
        updateImage()
    }
    
    @objc func swipeWgGesture(gesture: UISwipeGestureRecognizer) -> Void {
        switch gesture.direction {
        case .up : wg.moveFocus(-1)
        case .down : wg.moveFocus(+1)
        default : break
        }
    }
    
    //MARK: -
    
    func initializeWidgetGroup() {
        let gap:Float = -10
        wg.reset()
        wg.addToggle(.resolution)
        wg.addLine()
        wg.addSingleFloat(&control.zoom,  0.2,2, 0.03, "Zoom")
        wg.addSingleFloat(&control.scaleFactor,  -5.0,5.0, 0.1, "SFactor")
        wg.addSingleFloat(&control.epsilon,  0.00001, 0.0005, 0.0001, "epsilon")
        wg.addColor(.burningShip,Float(RowHT))
        wg.addCommand("B Ship",.burningShip)
        wg.addLine()
        wg.addGap(gap)
        wg.addFloat3Dual(&control.sphere, 0,2,0.03, "Sphere")
        wg.addFloat3Dual(&control.dSphere, 0.1,2,0.01, "△Sphere")
        wg.addSingleFloat(&control.sphereMult,  0.1,6.0,0.03, "S Mult")
        wg.addLine()
        wg.addGap(gap)
        wg.addFloat3Dual(&control.box, 0,2,0.01, "Box")
        wg.addFloat3Dual(&control.dBox, 0.1,2,0.01, "△Box")
        wg.addLine()
        wg.addGap(gap)
        wg.addToggle(.julia)
        wg.addTriplet(&control.julia,-10,10,0.1,"Julia")
        wg.addGap(gap)
        wg.addTriplet(&control.color,0,0.5,0.2,"Tint")
        wg.addTriplet(&control.lighting.position,-10,10,3,"Light")

        let sPmin:Float = 0.01
        let sPmax:Float = 1
        let sPchg:Float = 0.25
        wg.addSingleFloat(&control.lighting.diffuse,sPmin,sPmax,sPchg, "Bright")
        wg.addSingleFloat(&control.lighting.specular,sPmin,sPmax,sPchg, "Shiny")
        wg.addSingleFloat(&control.fog,0.3,2,0.2, "Fog")

        wg.addLine()
        wg.addGap(gap)
        wg.addToggle(.record)
        wg.addColor(.playBack,Float(RowHT))
        wg.addCommand("Play",.playBack)
        wg.addToggle(.speed)
        wg.addCommand("RecSave",.recSaveLoad)
        wg.addLine()
        wg.addCommand("Save/Load",.saveLoad)
        wg.addCommand("Help",.help)
        wg.addCommand("Reset",.reset)
        wg.addLine()
        wg.addCommand("Stereo",.stereo)
        wg.addLine()
        wg.addSingleFloat(&control.radialAngle,0,Float.pi,0.3, "Radial S")
    }
    
    //MARK: -
    
    func wgCommand(_ cmd: WgIdent) {
        switch(cmd) {
        case .saveLoad :
            saveLoadStyle = .settings
            performSegue(withIdentifier: "saveLoadSegue", sender: self)
        case .recSaveLoad :
            saveLoadStyle = .recordings
            performSegue(withIdentifier: "saveLoadSegue", sender: self)
        case .help :
            performSegue(withIdentifier: "helpSegue", sender: self)
        case .stereo :
            isStereo = !isStereo
            initializeWidgetGroup()
            layoutViews()
            updateImage()
        case .burningShip :
            control.isBurningShip = !control.isBurningShip
            defaultJbsSettings()
        case .playBack :
            record.playbackPressed()
            for m in [ cRotate,cTranslate,cTranslateZ ] as [UIView] { m.isHidden = record.state == .playing }
            parallax.isHidden = !isStereo
        case .reset :
            reset()
        default : break
        }
        
        wg.setNeedsDisplay()
    }
    
    func wgToggle(_ ident:WgIdent) {
        switch(ident) {
        case .resolution :
            isHighRes = !isHighRes
            setImageViewResolution()
            updateImage()
        case .julia :
            control.isJulia = !control.isJulia
            defaultJbsSettings()
            wg.focus += 5  // hop to companion control widgets
        case .record :
            record.recordPressed()
        case .speed :
            record.playSpeedPressed()
        default : break
        }
        
        wg.setNeedsDisplay()
    }
    
    func wgGetString(_ ident:WgIdent) -> String {
        switch ident {
        case .resolution :
            return isHighRes ? "Res: High" : "Res: Low"
        case .julia :
            return control.isJulia ? "Julia: On" : "Julia: Off"
        case .record :
            if record.getCount() > 0 { return String(format:"Rec %d",record.getCount()) }
            return "Record"
        case .speed :
            return String(format:"%d",record.numSteps)
        default : return ""
        }
    }

    func wgGetColor(_ ident:WgIdent) -> UIColor {
        var highlight:Bool = false
        switch(ident) {
        case .burningShip : highlight = control.isBurningShip
        case .playBack : highlight = record.state == .playing
        default : break
        }

        if highlight { return UIColor(red:0.2, green:0.2, blue:0, alpha:1) }
        return .black
    }
    
    func wgOptionSelected(_ ident:WgIdent, _ index: Int) {
        switch ident {
        //      case 1 : control.formula = Int32(index)
        default : break
        }
        
        //        updateImage()
    }
    
    func wgGetOptionString(_ ident:WgIdent) -> String {
        switch ident {
        //        case 1 : return fOptions[Int(control.formula)]
        default : return "noOption"
        }
    }
    
    //MARK: -
    
    @objc func timerHandler() {
        var refresh:Bool = false
        if cTranslate.update() { refresh = true }
        if cTranslateZ.update() { refresh = true }
        if cRotate.update() { refresh = true }
        if parallax.update() { refresh = true }
        if wg.update() { refresh = true }
        
        if record.state == .playing {
            if !isBusy {
                record.playBack()
                refresh = true
            }
        }
        
        if refresh && !isBusy { updateImage() }
    }
    
    //MARK: -
    
    func reset() {
        isHighRes = false
        record.reset()
        
        control.camera = vector_float3(0.35912, 2.42031, -0.376283)
        control.focus = vector_float3(0.35912, 2.52031, -0.376283)
        control.zoom = 0.6141
        control.epsilon = 0.000074
        control.scaleFactor = 3
        
        control.sphere.x = 0.25
        control.sphere.y = 1
        control.sphereMult = 4
        control.box.x = 1
        control.box.y = 2
        
        control.julia = float3()
        control.isJulia = false
        
        control.lighting.position = float3(0.2745, -0.0720005, 1.0)
        control.lighting.diffuse = 0.5

        control.color = float3(0.1)
        control.parallax = 0.0011
        control.fog = 3
        
        control.dBox = vector_float3(1,1,1)
        control.dSphere = vector_float3(1,1,1)
        
        aData.endPosition = arcBall.matrix3fSetIdentity()
        aData.transformMatrix = matrix_float4x4.init(diagonal: float4(1,1,1,1))
        
        alterAngle(0,0)
        updateImage()
    }
    
    func defaultJbsSettings() {
        var modifierCount = 0
        if control.isJulia { modifierCount += 1 }
        if control.isBurningShip { modifierCount += 1 }
        
        if modifierCount == 1 {
            control.camera = vector_float3(0.35912, 2.42031, -0.376283)
            control.focus = vector_float3(0.372051, 2.51716, -0.397411)
            control.julia = vector_float3(1.488, 0.893999, 0.0)
            aData.transformMatrix = simd_float4x4([0.420445, 0.139344, 0.89627, 0.0],[0.12931, 0.968464, -0.211281, 0.0],[-0.897794, 0.20482, 0.3896, 0.0],[0.0, 0.0, 0.0, 1.0])
            aData.endPosition = simd_float3x3([0.420445, 0.139344, 0.89627], [0.12931, 0.968464, -0.211281], [-0.897794, 0.20482, 0.3896])
        }
        else
        if modifierCount == 2 {
            control.camera = vector_float3(-0.130225, 2.91748, -0.496772)
            control.focus = vector_float3(-0.0428743, 2.96485, -0.486126)
            control.julia = vector_float3(-1.3435, 0.496, 0.7725)
            aData.transformMatrix = simd_float4x4([-0.133251, 0.444477, -0.885337, 0.0], [0.873522, 0.473633, 0.106464, 0.0], [0.467023, -0.759618, -0.45197, 0.0], [0.0, 0.0, 0.0, 1.0])
            aData.endPosition = simd_float3x3([-0.133251, 0.444477, -0.885337], [0.873522, 0.473633, 0.106464], [0.467023, -0.759618, -0.45197])
        }

        updateImage()
    }

    //MARK: -

    func controlJustLoaded() {
        wg.setNeedsDisplay()
        updateImage()
    }
    
    func setImageViewResolution() {
        control.xSize = Int32(metalTextureViewL.frame.width)
        control.ySize = Int32(metalTextureViewL.frame.height)
        if !isHighRes {
            control.xSize /= 2
            control.ySize /= 2
        }
        
        let xsz = Int(control.xSize)
        let ysz = Int(control.ySize)
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: xsz,
            height: ysz,
            mipmapped: false)
        
        outTextureL = self.device.makeTexture(descriptor: textureDescriptor)!
        outTextureR = self.device.makeTexture(descriptor: textureDescriptor)!
        
        metalTextureViewL.initialize(outTextureL)
        metalTextureViewR.initialize(outTextureR)
        
        let maxsz = max(xsz,ysz) + Int(threadGroupCount.width-1)
        threadGroups = MTLSizeMake(
            maxsz / threadGroupCount.width,
            maxsz / threadGroupCount.height,1)
    }
    
    //MARK: -
    
    func removeAllFocus() {
        if cTranslate.hasFocus { cTranslate.hasFocus = false; cTranslate.setNeedsDisplay() }
        if cTranslateZ.hasFocus { cTranslateZ.hasFocus = false; cTranslateZ.setNeedsDisplay() }
        if cRotate.hasFocus { cRotate.hasFocus = false; cRotate.setNeedsDisplay() }
        if parallax.hasFocus { parallax.hasFocus = false; parallax.setNeedsDisplay() }        
        if wg.hasFocus() { wg.removeAllFocus() }
    }
    
    func focusMovement(_ pt:CGPoint, _ touchCount:Int = 0) {
        if wg.hasFocus() { wg.focusMovement(pt,touchCount); return }
        if cTranslate.hasFocus { cTranslate.focusMovement(pt,touchCount); return }
        if cTranslateZ.hasFocus { cTranslateZ.focusMovement(pt,touchCount); return }
        if cRotate.hasFocus { cRotate.focusMovement(pt,touchCount); return }
        if parallax.hasFocus { parallax.focusMovement(pt) }
    }

    //MARK: -
    
    @objc func layoutViews() {
        let xs = view.bounds.width
        let ys = view.bounds.height
        var xBase = CGFloat()

        if !wg.isHidden {
            xBase = 120
            wg.frame = CGRect(x:0, y:0, width:xBase, height:ys)
        }
        
        if isStereo {
            metalTextureViewR.isHidden = false
            parallax.isHidden = false

            let xs2:CGFloat = (xs - xBase)/2
            metalTextureViewL.frame = CGRect(x:xBase, y:0, width:xs2, height:ys)
            metalTextureViewR.frame = CGRect(x:xBase+xs2+1, y:0, width:xs2, height:ys) // +1 = 1 pixel of bkground between
        }
        else {
            metalTextureViewR.isHidden = true
            parallax.isHidden = true
            metalTextureViewL.frame = CGRect(x:xBase, y:0, width:xs-xBase, height:ys)
        }

        // --------------------------------------------
        var x:CGFloat = xBase + 10
        var y:CGFloat = ys - 100

        func frame(_ xs:CGFloat, _ ys:CGFloat, _ dx:CGFloat, _ dy:CGFloat) -> CGRect {
            let r = CGRect(x:x, y:y, width:xs, height:ys)
            x += dx; y += dy
            return r
        }
        
        cTranslate.frame = frame(80,80,90,0)
        cTranslateZ.frame = frame(30,80,40,45)
        parallax.frame = frame(80,35,0,0)
        x = xs - 90
        y = ys - 100
        cRotate.frame = frame(80,80,0,0)
        
        arcBall.initialize(Float(cRotate.frame.width),Float(cRotate.frame.height))
        setImageViewResolution()
        updateImage()
    }
    
    //MARK: -
    
    func alterAngle(_ dx:Float, _ dy:Float) {
        let center:CGFloat = cRotate.bounds.width/2
        arcBall.mouseDown(CGPoint(x: center, y: center))
        arcBall.mouseMove(CGPoint(x: center + CGFloat(dx/50), y: center + CGFloat(dy/50)))
        
        let direction = simd_make_float4(0,0.1,0,0)
        let rotatedDirection = simd_mul(aData.transformMatrix, direction)
        
        control.focus.x = rotatedDirection.x
        control.focus.y = rotatedDirection.y
        control.focus.z = rotatedDirection.z
        control.focus += control.camera
        
        updateImage()
    }
    
    func alterPosition(_ dx:Float, _ dy:Float, _ dz:Float) {
        func axisAlter(_ dir:float4, _ amt:Float) {
            let diff = simd_mul(aData.transformMatrix, dir) * amt / 300.0
            
            func alter(_ value: inout float3) {
                value.x -= diff.x
                value.y -= diff.y
                value.z -= diff.z
            }
            
            alter(&control.camera)
            alter(&control.focus)
        }
        
        let q:Float = 0.1
        axisAlter(simd_make_float4(q,0,0,0),dx)
        axisAlter(simd_make_float4(0,0,q,0),dy)
        axisAlter(simd_make_float4(0,q,0,0),dz)
        
        updateImage()
    }
    
    //MARK: -
    
    var isBusy:Bool = false
    
    func updateImage() {
        if isBusy { return }
        isBusy = true

        control.deFactor1 = abs(control.scaleFactor - 1.0);
        control.deFactor2 = pow( Float(abs(control.scaleFactor)), Float(1 - 10));

        calcRayMarch(0)
        metalTextureViewL.display(metalTextureViewL.layer)
        
        if isStereo {
            calcRayMarch(1)
            metalTextureViewR.display(metalTextureViewR.layer)
        }
        
        isBusy = false
    }
    
    //MARK: -
    
    func calcRayMarch(_ who:Int) {
        func toRectangular(_ sph:float3) -> float3 { let ss = sph.x * sin(sph.z); return float3( ss * cos(sph.y), ss * sin(sph.y), sph.x * cos(sph.z)) }
        func toSpherical(_ rec:float3) -> float3 { return float3(length(rec), atan2(rec.y,rec.x), atan2(sqrt(rec.x*rec.x+rec.y*rec.y), rec.z)) }
        
        var c = control
        if who == 0 { c.camera.x -= control.parallax; c.focus.x += control.parallax } else { c.camera.x += control.parallax; c.focus.x -= control.parallax }
        
        c.viewVector = c.focus - c.camera
        c.topVector = toSpherical(c.viewVector)
        c.topVector.z += 1.5708
        c.topVector = toRectangular(c.topVector)
        c.sideVector = cross(c.viewVector,c.topVector)
        c.sideVector = normalize(c.sideVector) * length(c.topVector)
        c.lighting.position = normalize(c.lighting.position)
        
        cBuffer.contents().copyMemory(from: &c, byteCount:MemoryLayout<Control>.stride)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()!
        
        commandEncoder.setComputePipelineState(pipeline1)
        commandEncoder.setTexture(who == 0 ? outTextureL : outTextureR, index: 0)
        commandEncoder.setBuffer(cBuffer, offset: 0, index: 0)
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        commandEncoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}
