'From Cuis7.9 [latest update: #8340] on 14 November 2026 at 8:19:42 am'!
'Description HTTP bridge to drive a live Cuis image (eval + screenshots). Listens only on 127.0.0.1 and every request must carry the X-RemoteControl-Token header (see RemoteControl class>>token and >>tokenFile).'!
!provides: 'RemoteControl' '1.7.0'!
!requires: 'WebClient' '1.0.0' '1.*.*'!
!requires: 'Graphics-Files-Additional' '1.0.0' '1.*.*'!
SystemOrganization addCategory: #RemoteControl!


!classDefinition: #RemoteControl category: #RemoteControl!
Object subclass: #RemoteControl
	instanceVariableNames: ''
	classVariableNames: 'Port Server Token'
	poolDictionaries: ''
	category: 'RemoteControl'!
!classDefinition: 'RemoteControl class' category: #RemoteControl!
RemoteControl class
	instanceVariableNames: ''!


!RemoteControl class methodsFor: 'config' stamp: 'rcp 14/Nov/2026, 1:00:00 pm (UTC)'!
interface
	"The network interface the server binds to: loopback only, so the bridge is never
	reachable from other machines on the network (WebServer>>listenOn: alone binds to
	every interface). Deliberately not configurable."
	^ #[127 0 0 1]! !

!RemoteControl class methodsFor: 'config' stamp: 'ML 2/Jul/2026, 8:04:44 am (UTC)'!
port
	"The TCP port the eval/screenshot server listens on. Defaults to 2347; override with #port:
	(takes effect on the next #start). Configurable at runtime, no recompilation needed."
	^ Port ifNil: [2347]! !

!RemoteControl class methodsFor: 'config' stamp: 'ML 2/Jul/2026, 8:04:44 am (UTC)'!
port: aPortNumber
	"Set the listen port. Takes effect on the next #start. Answer the new port."
	^ Port := aPortNumber! !

!RemoteControl class methodsFor: 'config' stamp: 'rcp 14/Nov/2026, 1:00:00 pm (UTC)'!
tokenFile
	"Where #start writes the session token, so local tools can read it.
	RemoteControl tokenFile
	"
	^ DirectoryEntry userBaseDirectory // 'RemoteControl.token'! !

!RemoteControl class methodsFor: 'accessing' stamp: 'ML 12/May/2026, 8:52:33 pm (UTC)'!
isRunning
	^ Server notNil! !

!RemoteControl class methodsFor: 'accessing' stamp: 'ML 12/May/2026, 8:52:33 pm (UTC)'!
server
	^ Server! !

!RemoteControl class methodsFor: 'accessing' stamp: 'rcp 14/Nov/2026, 1:00:00 pm (UTC)'!
token
	"The value every request must send in the X-RemoteControl-Token header.
	A new one is generated on each #start and also written to #tokenFile.
	RemoteControl token
	"
	^ Token! !

!RemoteControl class methodsFor: 'lifecycle' stamp: 'rcp 14/Nov/2026, 1:00:00 pm (UTC)'!
start
	"Stop any previous server and start a fresh one on 127.0.0.1:self port.
	Every request must carry the header X-RemoteControl-Token: <self token>;
	the token is regenerated on each start and written to self tokenFile.
	Endpoints:
	  POST /eval        Smalltalk source body. Plain-text response.
	  GET  /screenshot  PNG of the world. Optional ?morph=Class or ?x&y&w&h to crop.
	For programmatic method compilation, use ClassDescription>>safelyCompile:classified:
	through /eval - much smaller surface, same safety."
	self stop.
	Token := self newToken.
	self tokenFile forceWriteStreamDo: [:stream | stream nextPutAll: Token].
	Server := WebServer new listenOn: self port interface: self interface.
	Server
		addService: '/eval'
			action: [:req | self handleEval: req]
			methods: #('POST').
	Server
		addService: '/screenshot'
			action: [:req | self handleScreenshot: req]
			methods: #('GET').
	^ Server! !

!RemoteControl class methodsFor: 'lifecycle' stamp: 'rcp 14/Nov/2026, 1:00:00 pm (UTC)'!
stop
	"Stop and forget the server and its token (idempotent).
	#destroy, unlike #stopListener, also closes the listening socket and open connections,
	so the port is released right away."
	Server ifNotNil: [:s | s destroy].
	Server := nil.
	Token := nil.
	self tokenFile exists ifTrue: [self tokenFile delete]! !

!RemoteControl class methodsFor: 'private' stamp: 'rcp 14/Nov/2026, 2:40:00 pm (UTC)'!
bodyOf: aRequest
	"The request body as text. HTTP bodies are bytes: decode them as UTF-8, the normal case.
	Bytes that are not valid UTF-8 are read as Latin-1 instead, which is what some clients send
	(curl on Windows converts command-line arguments to the ANSI code page).
	CharacterSequence class>>fromUtf8Bytes: does not reject invalid input (the resulting
	UnicodeString fails later, e.g. on #size), so validity is checked first."
	| bytes |
	bytes := aRequest content asByteArray.
	^ (self isValidUtf8: bytes)
		ifTrue: [CharacterSequence fromUtf8Bytes: bytes]
		ifFalse: [bytes asString]! !

!RemoteControl class methodsFor: 'private' stamp: 'ML 28/May/2026, 1:57:08 pm (UTC)'!
cropRectFor: morph pad: pad in: bigRect
	"World-coordinate crop rectangle for morph: its displayFullBounds (geometric -- works even for
	a fully-transparent morph, where displayBounds is nil, and includes the morph submorphs),
	expanded by pad on every side, then clamped to the form."
	| b |
	b := morph displayFullBounds.
	^ ((b origin - pad) corner: (b corner + pad)) intersect: bigRect! !

!RemoteControl class methodsFor: 'private' stamp: 'rcp 14/Nov/2026, 1:00:00 pm (UTC)'!
isAuthorized: aRequest
	"Does aRequest carry the current session token? Header names are case-insensitive.
	Besides keeping out other local processes, this blocks web pages: a browser cannot add a
	custom header to a cross-origin request without a CORS preflight, which is never granted here."
	^ Token notNil and: [(aRequest headerAt: 'X-RemoteControl-Token') = Token]! !

!RemoteControl class methodsFor: 'private' stamp: 'rcp 14/Nov/2026, 2:40:00 pm (UTC)'!
isValidUtf8: aByteArray
	"Is aByteArray well-formed UTF-8 (no overlong 2-byte lead bytes, no lead bytes past U+10FFFF)?"
	| index size extra |
	index := 1.
	size := aByteArray size.
	[index <= size] whileTrue: [ | lead |
		lead := aByteArray at: index.
		extra := lead < 16r80
			ifTrue: [0]
			ifFalse: [(lead between: 16rC2 and: 16rDF)
				ifTrue: [1]
				ifFalse: [(lead between: 16rE0 and: 16rEF)
					ifTrue: [2]
					ifFalse: [(lead between: 16rF0 and: 16rF4)
						ifTrue: [3]
						ifFalse: [^ false]]]].
		index + extra > size ifTrue: [^ false].
		1 to: extra do: [:offset |
			((aByteArray at: index + offset) between: 16r80 and: 16rBF) ifFalse: [^ false]].
		index := index + extra + 1].
	^ true! !

!RemoteControl class methodsFor: 'private' stamp: 'rcp 14/Nov/2026, 1:00:00 pm (UTC)'!
newToken
	"32 random hexadecimal digits."
	^ String streamContents: [:stream |
		32 timesRepeat: [stream nextPut: '0123456789abcdef' atRandom]]! !

!RemoteControl class methodsFor: 'private' stamp: 'ML 3/Jul/2026, 1:40:41 pm (UTC)'!
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
		UISupervisor ui allMorphsDo: [:m |
			(morph isNil and: [m identityHash printString = idString]) ifTrue: [morph := m]].
		morph ifNil: [^ self error: 'Morph not found by id: ', idString].
		^ self cropRectFor: morph pad: pad in: bigRect].
	morphName := params at: 'morph' ifAbsent: [nil].
	morphName ifNotNil: [
		morph := nil.
		UISupervisor ui allMorphsDo: [:m |
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

!RemoteControl class methodsFor: 'private' stamp: 'rcp 14/Nov/2026, 2:40:00 pm (UTC)'!
renderWorld
	"A clean re-render of the world, done inside the Morphic UI process.
	Rendering from the WebServer's request process races with the UI process inside the
	VectorEngine: the UI process can fail with 'resume failed' (opening a Debugger) and the
	request never answers. Answers the Form, or signals an error after 10 seconds if the UI
	process does not get to it (for instance, while a modal dialog is open)."
	| done form problem |
	done := Semaphore new.
	UISupervisor whenUIinSafeState: [
		[form := UISupervisor ui imageForm: 32]
			on: Error
			do: [:error | problem := error messageText. error return: nil].
		done signal].
	(done waitTimeoutMSecs: 10000) ifTrue: [
		^ self error: 'Timed out waiting for the UI process to render the world (try ?raw=1)'].
	problem ifNotNil: [^ self error: problem].
	^ form! !

!RemoteControl class methodsFor: 'private' stamp: 'rcp 14/Nov/2026, 1:00:00 pm (UTC)'!
sendForbidden: aRequest
	^ aRequest sendResponseCode: 403
		content: 'Missing or wrong X-RemoteControl-Token header. Read the token from RemoteControl tokenFile (or evaluate RemoteControl token in the image).' asUtf8Bytes
		type: 'text/plain; charset=utf-8'
		close: true! !

!RemoteControl class methodsFor: 'handlers' stamp: 'ML 26/May/2026, 8:02:54 am (UTC)'!
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

!RemoteControl class methodsFor: 'handlers' stamp: 'rcp 14/Nov/2026, 2:18:39 pm (UTC)'!
handleScreenshot: aRequest
	"PNG bytes with 200, or plain-text error with 500.
	Query crop: ?id=<identityHash> | ?morph=<ClassName> | ?x&y&w&h, plus optional ?pad=<n>.
	?raw=1 captures the LIVE Display buffer (actual on-screen pixels -- shows drag trails and any
	stale/uninvalidated regions); the default re-renders the world in the UI process (always clean,
	so it hides such artifacts)."
	(self isAuthorized: aRequest) ifFalse: [^ self sendForbidden: aRequest].
	[
		| form rect query params raw bytes |
		query := aRequest rawUrl copyAfter: $?.
		params := query isEmptyOrNil ifTrue: [Dictionary new] ifFalse: [WebUtils decodeUrlEncodedForm: query].
		raw := (params at: 'raw' ifAbsent: ['0']) = '1'.
		form := raw
			ifTrue: [Display]
			ifFalse: [self renderWorld].
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

!RemoteControl class methodsFor: 'requests' stamp: 'rcp 14/Nov/2026, 2:18:39 pm (UTC)'!
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
	(self isAuthorized: aRequest) ifFalse: [^ self sendForbidden: aRequest].
	body := self bodyOf: aRequest.
	((Utilities authorInitialsPerSe ifNil: ['']) isEmpty and: [(body includesSubString: 'setAuthor') not]) ifTrue: [
		^ aRequest sendResponseCode: 400 content: (String streamContents: [:s |
			s nextPutAll: 'Author initials not set -- Cuis would open a blocking dialog on the first method compile, stalling the image.'; newLine.
			s nextPutAll: 'Ask your human which name and initials to use, then run over this bridge:'; newLine.
			s nextPutAll: '  Utilities setAuthorInitials: ''XY'' name: ''Your Name'''; newLine.
			s nextPutAll: 'and retry your request.']) asUtf8Bytes type: 'text/plain; charset=utf-8' close: true].
	[[[
		| value |
		value := Compiler evaluate: body.
		^ aRequest send200Response: value printString asUtf8Bytes contentType: 'text/plain; charset=utf-8'
	] on: UndeclaredVariableReference do: [:ex |
		aRequest sendResponseCode: 400 content: ('Undeclared variable: ' , ex varName) asUtf8Bytes type: 'text/plain; charset=utf-8' close: true]
	] on: Notification do: [:ex | ex resume: true]
	] on: Error do: [:ex |
		aRequest sendResponseCode: 500 content: (self errorReportFor: ex) asUtf8Bytes type: 'text/plain; charset=utf-8' close: true]! !

!ClassDescription methodsFor: '*RemoteControl' stamp: 'ML 13/May/2026, 5:31:26 am (UTC)'!
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
