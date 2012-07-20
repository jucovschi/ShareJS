# :tabSize=4:indentSize=4:

# This is some utility code to connect an ace editor to a sharejs document.

if WEB?
	if typeof window.require == "undefined" && window.ace.require 
		window.require = window.ace.require
	Range = require("ace/range").Range
	event = require("pilot/event");
	ace = {}
	
getStartOffsetPosition = (editorDoc, range) ->
    # This is quite inefficient - getLines makes a copy of the entire
    # lines array in the document. It would be nice if we could just
    # access them directly.
    lines = editorDoc.getLines 0, range.start.row
    
    offset = 0

    for line, i in lines
      offset += if i < range.start.row
        line.length
      else
        range.start.column

    # Add the row number to include newlines.
    offset + range.start.row
	
# Convert an ace delta into an op understood by share.js
applyToShareJS = (editorDoc, delta, doc) ->
  # Get the start position of the range, in no. of characters


  pos = getStartOffsetPosition(editorDoc, delta.range)

  switch delta.action
    when 'insertText' then doc.insert pos, delta.text
    when 'removeText' then doc.del pos, delta.text.length
    
    when 'insertLines'
      text = delta.lines.join('\n') + '\n'
      doc.insert pos, text
      
    when 'removeLines'
      text = delta.lines.join('\n') + '\n'
      doc.del pos, text.length

    else throw new Error "unknown action: #{delta.action}"
  
  return

getComposedType = (oldTokenType, meta) ->
	for m in meta.attributes
		if m.key == "hider"
			return oldTokenType+".hider";
		if m.key == "label"
			return oldTokenType+".label";
		if m.key == "ref"
			return oldTokenType+".ref";
		if m.key == "hider.expanded"
			return oldTokenType+".exphider";
		if m.key == "error"
			return oldTokenType+".error";
	return oldTokenType
  
mergeTokens = (offset, meta, tokens) ->
	if meta.length == 0
		return tokens
	resultTokens = [];
	metaIndex = 0;
	cOffset = offset;
	for token in tokens 
		startOffset = cOffset;
		endOffset = cOffset + token.value.length
		while metaIndex < meta.length
			#console.log("current ", cOffset, startOffset, endOffset, meta[metaIndex])
			# we iterated past current token
			if cOffset > endOffset
				cOffset = endOffset
				break;
			# current token is fully before leftmost metadata
			# so we just push it to the result
			if meta[metaIndex].start > endOffset
				resultTokens.push({
					type: token.type
					value: token.value.substr(cOffset-startOffset, endOffset-cOffset)
					});
				cOffset = endOffset 
				#console.log("iterated pas current token");
				break
			# current meta was already consumed
			if meta[metaIndex].end <= cOffset
				#console.log("current meta was consumed");
				metaIndex++
				continue
			 meta starts later than current token
			if cOffset < meta[metaIndex].start
				#console.log("meta starts later");
				resultTokens.push({
					type: token.type
					value: token.value.substr(cOffset-startOffset, meta[metaIndex].start-cOffset)
					});
				cOffset = meta[metaIndex].start
				continue;

			# cOffset is at the begining or in the middle of a meta
			#console.log("begining or middle of meta");
			endPos = Math.min(endOffset, meta[metaIndex].end);
			resultTokens.push({
				type: getComposedType(token.type, meta[metaIndex]),
				value: token.value.substr(cOffset-startOffset, endPos-cOffset)
			});
			cOffset = Math.max(endPos, cOffset+1)

		# if tokens available but no more metadata then just push them to the end
		if metaIndex == meta.length && cOffset < endOffset
			resultTokens.push({
					type: token.type
					value: token.value.substr(cOffset-startOffset, endOffset-cOffset)
					});
			cOffset = endOffset
	resultTokens

  
# Attach an ace editor to the document. The editor's contents are replaced
# with the document's contents unless keepEditorContents is true. (In which case the document's
# contents are nuked and replaced with the editor's).
window.sharejs.extendDoc 'attach_ace', (editor, keepEditorContents) ->

  throw new Error 'Only text documents can be attached to ace' unless @provides['text']
  doc = this
  editorDoc = editor.getSession().getDocument()
  editorDoc.setNewLineMode 'unix'

  check = ->
    window.setTimeout ->
        editorText = editorDoc.getValue()
        otText = doc.getText()

        if editorText != otText
          console.error "Text does not match!"
          console.error "editor: #{editorText}"
          console.error "ot:     #{otText}"
          # Should probably also replace the editor text with the doc snapshot.
      , 0

  if keepEditorContents
    doc.del 0, doc.getText().length
    doc.insert 0, editorDoc.getValue()
  else
    editorDoc.setValue doc.getText()

  check()

  # When we apply ops from sharejs, ace emits edit events. We need to ignore those
  # to prevent an infinite typing loop.
  suppress = false
  
  # Listen for edits in ace
  editorListener = (change) ->
    return if suppress
    applyToShareJS editorDoc, change.data, doc

    check()

  replaceMode = (editor) ->
  	  if (typeof doc.getMeta == "undefined")
  	  	return;
  	  oldMode = editor.getSession().getMode();
  	  oldTokenizer = oldMode.getTokenizer();
  	  oldGetLineTokens = oldTokenizer.getLineTokens;
  	  oldTokenizer.getLineTokens = (line, state) ->
  	  	  shouldMergeTokens = true
  	  	  if (typeof state == "string" || typeof state == "undefined" )
  	  	  	  shouldMergeTokens = false
  	  	  	  state = {
  	  	  	  	line: 0;
  	  	  	  	offset: 0;
  	  	  	  	state: state;
  	  	  	  };
  	  	  result = oldGetLineTokens.apply(oldTokenizer, [line, state.state]);
  	  	  meta = doc.getMeta(state.offset, line.length);
  	  	  if shouldMergeTokens && meta.length > 0
  	  	  	  result.tokens = mergeTokens(state.offset, meta, result.tokens);
  	  	  result.state = {
  	  	  	line : state.line + 1,
  	  	  	offset : state.offset + line.length + 1
  	  	  	state : result.state;
  	  	  };
  	  	  return result

  showDialog = (title, html, pos, btn) ->
  	  jQuery("body").append jQuery("<div>").attr("id", "ui-context").append("<p>Generic Text</p>")
  	  jQuery("#ui-context").each (idx, obj) ->
  	  	  jQuery(obj).empty()
  	  	  obj.innerHTML = html.join(" ")
  	  	  console.log "trying to show " + obj
  	  	  jQuery(obj).dialog {
  	  	  	title: title
  	  	  	position: [ pos.x, pos.y ]
  	  	  	buttons: btn
  	  	  }

 	  	  
  hideDialog = ->
  	  jQuery("#ui-context").each (idx, obj) ->
  	  	  jQuery(obj).empty()
  	  	  
  menuDisplay = (evt) ->
  	  showDialog("Hidden ", ["help", "trep"]);

  handleMouseEvent = (event, pos, screenPos) ->
  	  offset = getStartOffsetPosition(editorDoc, {start : pos});
  	  if (typeof doc.getMeta == "undefined")
  	  	return;
  	  meta = doc.getMeta(offset, 1);
  	  if typeof meta[0] == "undefined"
  	  	  return;
  	  for attr in meta[0].attributes
  	  	  if attr.key==event
  	  	  	  data = attr.value.split(".");  	  	  	  
  	  	  	  doc.emitRemote(data[0], event, { service:data.slice(1), screenPos:screenPos, docPos:pos, offset: offset}, menuDisplay)
  	  	  	  
  hookMouseEvents = (editor) ->
  	  editor.addEventListener("mousedown", (e) ->
  	  	  console.log(e.getButton())
  	  	  # Right button clicked
  	  	  if (e.getButton() == 2)
  	  	  	  handleMouseEvent("rightClick", e.getDocumentPosition(), {x:e.pageX, y:e.pageY});
  	  	  if (e.getButton() == 0)
  	  	  	  handleMouseEvent("leftClick", e.getDocumentPosition(), {x:e.pageX, y:e.pageY});
  	  )
  	  editor.addEventListener("dblclick", (e) ->
  	  	  handleMouseEvent("dblClick", e.getDocumentPosition(), {x:e.pageX, y:e.pageY});
  	  )

  replaceMode(editor);
  hookMouseEvents(editor);
  editorDoc.on 'change', editorListener

  # Listen for remote ops on the sharejs document
  docListener = (op) ->
    suppress = true
    applyToDoc editorDoc, op
    suppress = false

    check()


  # Horribly inefficient.
  offsetToPos = (offset) ->
    # Again, very inefficient.
    lines = editorDoc.getAllLines()

    row = 0
    for line, row in lines
      break if offset <= line.length

      # +1 for the newline.
      offset -= lines[row].length + 1

    row:row, column:offset

  doc.on 'insert', (pos, text) ->
    suppress = true
    editorDoc.insert offsetToPos(pos), text
    suppress = false
    check()

  doc.on 'delete', (pos, text) ->
    suppress = true
    range = Range.fromPoints offsetToPos(pos), offsetToPos(pos + text.length)
    editorDoc.remove range
    suppress = false
    check()

    
  doc.detach_ace = ->
    doc.removeListener 'remoteop', docListener
    editorDoc.removeListener 'change', editorListener
    delete doc.detach_ace

  return

