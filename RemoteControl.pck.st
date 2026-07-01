'From Cuis7.7 [latest update: #7948] on 1 July 2026 at 1:38:22 pm'!
'Description '!
!provides: 'RemoteControl' 1 2!
!requires: 'WebClient' 1 nil 1!
!requires: 'Graphics-Files-Additional' 1 nil 1!
SystemOrganization addCategory: #RemoteControl!


!classDefinition: #RemoteControl category: #RemoteControl!
Object subclass: #RemoteControl
	instanceVariableNames: ''
	classVariableNames: 'Server'
	poolDictionaries: ''
	category: 'RemoteControl'!
!classDefinition: 'RemoteControl class' category: #RemoteControl!
RemoteControl class
	instanceVariableNames: ''!


!RemoteControl class methodsFor: 'config' stamp: 'ML 13/May/2026 07:52:35'!
port ^ 2347! !

!RemoteControl class methodsFor: 'accessing' stamp: 'ML 12/May/2026 22:52:33'!
isRunning
	^ Server notNil! !

!RemoteControl class methodsFor: 'accessing' stamp: 'ML 12/May/2026 22:52:33'!
server
	^ Server! !

!RemoteControl class methodsFor: 'lifecycle' stamp: 'ML 1/Jul/2026 12:47:10'!
start
	"Stop any previous server and start a fresh one on self port.
	Endpoints:
	  POST /eval        Smalltalk source body. JSON response.
	  GET  /screenshot  PNG of the world. Optional ?morph=Class or ?x&y&w&h to crop.
	For programmatic method compilation, use ClassDescription>>safelyCompile:classified:
	through /eval - much smaller surface, same safety."
	self stop.
	Server := WebServer new listenOn: self port.
	Server
		addService: '/eval'
			action: [:req | self handleEval: req]
			methods: #('POST').
	Server
		addService: '/screenshot'
			action: [:req | self handleScreenshot: req]
			methods: #('GET').
	^ Server! !

!RemoteControl class methodsFor: 'lifecycle' stamp: 'ML 12/May/2026 22:55:44'!
stop
	"Stop and forget the server (idempotent)."
	Server ifNotNil: [:s | s stopListener].
	Server := nil! !

!RemoteControl class methodsFor: 'handlers' stamp: 'ML 26/May/2026 10:02:54'!
errorReportFor: anException
	"500 body for a runtime error: a ClassName: message header line, then a short stack trace
	trimmed at the user DoIt frame (so the Compiler/bridge harness frames below it are dropped)
	and capped at 15 frames."
	| report frames doItIndex |
	report := String new writeStream.
	report nextPutAll: anException class name asString; nextPutAll: ': '; nextPutAll: (anException messageText ifNil: [String new]).
	anException signalerContext ifNotNil: [:ctx |
		frames := ctx stackOfSize: 40.
		doItIndex := frames findFirst: [:f | f printString = 'UndefinedObject>>DoIt'].
		doItIndex > 0 ifTrue: [frames := frames first: doItIndex].
		frames := frames first: (frames size min: 15).
		report newLine; nextPutAll: 'Stack:'.
		frames do: [:f | report newLine; nextPutAll: '  '; nextPutAll: f printString]].
	^ report contents! !

!RemoteControl class methodsFor: 'handlers' stamp: 'ML 26/May/2026 10:03:06'!
handleEval: aRequest
	"Evaluate the request body as Smalltalk and reply.
	- success: 200 with the result printString.
	- undeclared variable (e.g. a Squeak/Pharo class name absent from this image): 400 naming the
	  variable. The parser raises UndeclaredVariableReference (a Notification carrying the name)
	  during parsing; the inner handler reports it before the outer blanket resume can swallow it.
	- any other benign Notification: auto-resumed with true.
	- any other runtime Error: 500 with a header line plus a short stack trace.
	Bodies are sent as UTF-8 bytes so char-count equals byte-count: WebRequest uses #size as the
	Content-Length while encoding UTF-8 on the wire, so a non-ASCII String would corrupt framing."
	| body |
	body := aRequest content asString.
	[[[
		| value |
		value := Compiler evaluate: body.
		^ aRequest send200Response: value printString asUtf8Bytes contentType: 'text/plain; charset=utf-8'
	] on: UndeclaredVariableReference do: [:ex |
		aRequest sendResponseCode: 400 content: ('Undeclared variable: ' , ex varName) asUtf8Bytes type: 'text/plain; charset=utf-8' close: true]
	] on: Notification do: [:ex | ex resume: true]
	] on: Error do: [:ex |
		aRequest sendResponseCode: 500 content: (self errorReportFor: ex) asUtf8Bytes type: 'text/plain; charset=utf-8' close: true]! !

!RemoteControl class methodsFor: 'handlers' stamp: 'ML 28/May/2026 16:21:49'!
handleScreenshot: aRequest
	"PNG bytes with 200, or plain-text error with 500.
	Query crop: ?id=<identityHash> | ?morph=<ClassName> | ?x&y&w&h, plus optional ?pad=<n>.
	?raw=1 captures the LIVE Display buffer (actual on-screen pixels -- shows drag trails and any
	stale/uninvalidated regions); the default re-renders the world via imageForm: (always clean,
	so it hides such artifacts)."
	[
		| form rect query params raw bytes |
		query := aRequest rawUrl copyAfter: $?.
		params := query isEmptyOrNil ifTrue: [Dictionary new] ifFalse: [WebUtils decodeUrlEncodedForm: query].
		raw := (params at: 'raw' ifAbsent: ['0']) = '1'.
		form := raw
			ifTrue: [Display]
			ifFalse: [(WorldMorph allInstances first) imageForm: 32].
		rect := self rectFromQuery: query in: form boundingBox.
		(rect notNil and: [rect area > 0]) ifTrue: [form := form copy: rect].
		bytes := ByteArray streamContents: [:s | PNGReadWriter putForm: form onStream: s].
		^ aRequest send200Response: bytes contentType: 'image/png'
	] on: Error do: [:ex |
		| msg |
		msg := ex class name asString, ': ', (ex messageText ifNil: ['']).
		aRequest sendResponseCode: 500
			content: msg asUtf8Bytes
			type: 'text/plain; charset=utf-8'
			close: true]! !

!RemoteControl class methodsFor: 'private' stamp: 'ML 28/May/2026 15:57:08'!
cropRectFor: morph pad: pad in: bigRect
	"World-coordinate crop rectangle for morph: its displayFullBounds (geometric -- works even for
	a fully-transparent morph, where displayBounds is nil, and includes the morph submorphs),
	expanded by pad on every side, then clamped to the form."
	| b |
	b := morph displayFullBounds.
	^ ((b origin - pad) corner: (b corner + pad)) intersect: bigRect! !

!RemoteControl class methodsFor: 'private' stamp: 'ML 28/May/2026 15:57:08'!
rectFromQuery: queryString in: bigRect
	"Returns a Rectangle, or nil if the query has no crop intent. Raises Error if there IS crop
	intent but it can not be honored (unknown morph/id; partial x/y/w/h spec).
	Crop intents: ?id=<identityHash> (one specific morph -- unambiguous), ?morph=<ClassName> (first
	morph of that class), or explicit ?x&y&w&h. Any morph crop honours an optional ?pad=<n> margin
	and uses displayFullBounds so transparent morphs and submorphs are handled."
	| params morph idString morphName hasCoord allCoord pad |
	queryString isEmptyOrNil ifTrue: [^ nil].
	params := WebUtils decodeUrlEncodedForm: queryString.
	pad := (params at: 'pad' ifAbsent: ['0']) asNumber.
	idString := params at: 'id' ifAbsent: [nil].
	idString ifNotNil: [
		morph := nil.
		WorldMorph allInstances first allMorphsDo: [:m |
			(morph isNil and: [m identityHash printString = idString]) ifTrue: [morph := m]].
		morph ifNil: [^ self error: 'Morph not found by id: ', idString].
		^ self cropRectFor: morph pad: pad in: bigRect].
	morphName := params at: 'morph' ifAbsent: [nil].
	morphName ifNotNil: [
		morph := nil.
		WorldMorph allInstances first allMorphsDo: [:m |
			(morph isNil and: [m class name asString = morphName]) ifTrue: [morph := m]].
		morph ifNil: [^ self error: 'Morph not found: ', morphName].
		^ self cropRectFor: morph pad: pad in: bigRect].
	hasCoord := #('x' 'y' 'w' 'h') anySatisfy: [:k | params includesKey: k].
	hasCoord ifFalse: [^ nil].
	allCoord := #('x' 'y' 'w' 'h') allSatisfy: [:k | params includesKey: k].
	allCoord ifFalse: [^ self error: 'Need all of x, y, w, h'].
	^ (((params at: 'x') asNumber) @ ((params at: 'y') asNumber)
		extent: ((params at: 'w') asNumber) @ ((params at: 'h') asNumber))
		intersect: bigRect! !

!ClassDescription methodsFor: '*RemoteControl' stamp: 'ML 13/May/2026 07:31:26'!
safelyCompile: source classified: aCategory
	"Compile one method, with the three things bridge callers always want:
	  - Noisy Notifications (InMidstOfFileinNotification, UndeclaredVariableWarning, ...)
	    are resumed so they don't poison the compile.
	  - The method is stamped via Utilities changeStamp.
	  - Smalltalk forceChangesToDisk runs so #authorAndStamp is readable immediately.
	Returns the compiled selector. Errors propagate.

	   Dock safelyCompile: 'foo ^ 42' classified: 'misc'
	   Dock class safelyCompile: 'hi ^ ''hello''' classified: 'misc'
	"
	| selector |
	[
		selector := self
			compile: source
			classified: aCategory
			withStamp: Utilities changeStamp
			notifying: nil
	] on: Notification do: [:ex | ex resume: true].
	Smalltalk forceChangesToDisk.
	^ selector! !
