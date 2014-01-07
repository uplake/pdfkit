LineWrapper = require '../line_wrapper'

doTests = require.main is module # run tests when executing this file directly

class Style
    @styles: ->
        style = new Style
        (key for own key of style)

    constructor: ->
        unless this instanceof Style
            return new Style arguments...
        @noStyle()

    noStyle: -> 
        @italic = no
        @underline = no
        @strikethrough = no
        @bold = no

    isEqual: (aStyle) ->
        for own key, val of this
            return no unless aStyle[key] is val
        yes

if doTests
    assert =  require 'assert'
    style1 = new Style
    style2 = Style()
    assert style1.isEqual style2
    style1.italic = yes
    assert not style1.isEqual style2

    styles = Style.styles()
    for style in ['italic', 'underline', 'strikethrough', 'bold']
        assert style in styles, "#{style} unexpectedly absent from Style.styles()"

{defineProperty} = Object
class Word
    @bindToDoc: (@doc) ->
    @widthOfString: (word) -> @doc?.widthOfString(word) ? 0
    @lineHeight: -> @doc?.currentLineHeight() ? 0

    constructor: (@word, x, y) ->
        unless this instanceof Word
            return new Word arguments...
        @offset = 0
        @rect = {
            x, y
            w: @constructor.widthOfString @word
            h: @constructor.lineHeight()
        }
        @style = new Style

    defineProperty @::, 'length', get: -> @word.length

    toString: -> @word.toString()

if doTests
    PDFDoc = require('../document')
    doc = new PDFDoc
    Word.bindToDoc doc
    word1 = Word("monkey", 0, 0)
    word2 = Word("yeknom", 50, 0)
    word3 = Word("baboon", 100, 0)
    for key, val of word1.rect when key isnt 'y'
        assert word2.rect[key] is val unless key is 'x'
        assert word3.rect[key] isnt val unless key is 'h'

{max, min} = Math
class Line
    constructor: (@words, @separator = '') ->
        unless this instanceof Line
            return new Line arguments...
        @offset = 0
        @initialize()

    initialize: ->
        x = y = Infinity
        maxX = maxY = -Infinity
        w = h = 0
        length = 0
        for word in @words
            {rect} = word
            word.offset = length
            length += word.length
            x = min rect.x, x
            y = min rect.y, y
            maxX = max rect.x + rect.w, maxX
            maxY = max rect.y + rect.h, maxY

        @length = length

        @rect = {x, y, w: maxX - x, h: maxY - y}

    toString: -> @words.join @separator

if doTests
    line = Line [word1, word2, word3], ' '
    assert.equal line.toString(), "#{word1} #{word2} #{word3}"
    assert.equal test = line.rect.x, expect = word1.rect.x,
        "unexpected x of line, '#{line}': #{test}, #{expect}"
    assert.equal test = line.rect.y, expect = word1.rect.y,
        "unexpected y of line, '#{line}': #{test}, #{expect}"
    assert.equal test = line.rect.w, expect = word3.rect.x + doc.widthOfString(word3),
        "unexpected width of line, '#{line}': #{test}, #{expect}"

class TextBlock
    constructor: (@lines) ->
        unless this instanceof TextBlock
            return new TextBlock arguments...
        @initialize()

    initialize: ->
        length = 0
        for line in @lines
            line.offset = length
            length += line.length
        @length = length

    applyStyle: (pattern, style, onOrOff) ->
        string = @lines.join ''
        string.replace pattern, (match, args...) ->
            offset = args[-2...-1]
            length = match.length

    for style in Style.styles()
        do (style) ->
            defineProperty @::, style, value: (pattern, onOrOff = yes) -> 
                @applyStyle pattern, style, onOrOff

    toString: -> @lines.join '\n' 

if doTests
    f = (a, b..., c, d) -> console.log a, b, c, d
    "Hi there".replace /e/g, (match, args...) -> console.log match, args[-2...-1]
    f(1, 3)

###
PDFKit has a LineWrapper object, but it can't be used to determine a text layout before committing it to the document, and it doesn't expose the actual widths for each line of text. Often, it is useful to know the actual dimensions that a block of text would occupy before writing that text to a document. For example, you might be dynamically laying out a document, and you want to try different options to see what works best. Alternately, you might want to draw a box tight around a multiline block of text. 

This method takes a string and a width (and optional x and y) and returns an array of String objects representing each line of the text, broken according to the width. Each line has a 'rect' property with x, y, width, and height position metadata. Additionally, the array itself has similar position metadata. The array can be coerced into a hard-wrapped string.
###
exports.splitToWidth = (text, x, y, options = {}) ->

    options = @_initOptions(x, y, options)

    text = '' + text
                
    # if the wordSpacing option is specified, remove multiple consecutive spaces
    if options.wordSpacing
        text = text.replace(/\s{2,}/g, ' ')

    options.align ?= 'left'
    options.lineHeight ?= @document.currentLineHeight()
        
    paragraphs = text.split '\n'

    lines = [] # output object
    maxLineWid = 0
    lineGap = options.lineGap or @_lineGap or 0
    doLine = (text, options) ->
        # make a string object we can attach metadata to
        strObj = new String text 

        # determine position metadata for current line
        x = @document.x
        switch options.align
            when 'right'
                x += options.lineWidth - options.textWidth
            when 'center'
                x += options.lineWidth / 2 - options.textWidth / 2

        rect = 
            x: x
            y: @document.y
            w: options.textWidth
            h: options.lineHeight
      
        # add position metadata to String object
        defineProperty strObj, 'rect', value: rect 

        # add string object to lines
        lines.push strObj
        maxLineWid = max rect.w, maxLineWid
        @document.y += rect.h + lineGap

    # word wrapping
    if options.width
        # create an object that will behave like a PDFDocument as far as the LineWrapper is concerned
        dummyDoc = 
            x: options.x
            y: options.y
            options: @options
            widthOfString: @widthOfString.bind(@)
            currentLineHeight: @currentLineHeight.bind(@)

        # make a wrapper that will not affect the real document
        wrapper = new LineWrapper dummyDoc 

        wrapper.on 'line', doLine

        # have wrapper process the input string
        wrapper.wrap paragraphs, options

    else # no word wrapping
        lines = (doLine(para) for para in paragraphs)

    # lines is an array of String objects with position metadata for each line
    # determine position metadata for the entire block of text
    rect =  
        x: options.x
        y: options.y
        w: maxLineWid
        h: lines.length * @currentLineHeight(true)

    # add position metadata for the block of text
    for key, value of {
        rect: rect
        width: rect.w 
        height: rect.h

        # with this function, the lines array can be coerced to a string, meaning that it can be passed as-is to doc.text or certain other functions that expect a string. But it's safest to call toString() explicitly before sending the object into some random function.
        toString: -> @join '\n' 
    }
        defineProperty lines, key, {value}

    lines
