{defineProperty, defineProperties} = Object

clone = (obj, excludeKeys...) ->
    return obj  if obj is null or typeof (obj) isnt "object"
    temp = new obj.constructor()
    for key of obj when not key in excludeKeys
        temp[key] = clone(obj[key])
    temp

class StringLike extends String
    initialize: (options) ->
        for key, value of options
            @[key] = value
    clone: ->
        copy = new @constructor
        for own key, val of this
            copy[key] = clone val
        copy

    valueOf: -> @toString()
    defineProperty @::, 'length', get: -> @toString().length

class Word extends StringLike
    constructor: (@string, options = {}) ->
        @initialize options
        @offset ?= 0

    unusedChars: -> @string[...@offset]

    toString: -> @string[@offset..]

class Line extends StringLike
    constructor: (@words, options = {}) ->
        @initialize options

    toString: -> @words.join ''

class TextMap

    constructor: (@originalText, @doc) ->
        @unconsumedText = originalText[..]
        @consumedCharCount = 0

        @lines = []
        @wordData = []
        @wordDataIndices = []
        @pageIndex = doc.pages.indexOf doc.page 
        @rects = [@initRect()]

        @fontSpec = doc.currentFontSpec()

    initRect: ->
        @rect = 
            x: @doc.page.width
            y: @doc.page.height
            w: 0
            h: 0
            pageIndex: @pageIndex
        @rect

    addLine: (words, x, y, wordSpacing, options) ->
        @options ?= options
        {page} = @doc
        pageIndex = @doc.pages.indexOf page 
        if pageIndex isnt @pageIndex
            @pageIndex = pageIndex
            @rects.push @initRect()

        @rect.x = Math.min @rect.x, x
        @rect.y = Math.min @rect.y, y

        lineProps = {
            x, y, pageIndex
            w: @doc.widthOfString(words.join(''), options)
            h: @doc.currentLineHeight(yes)
        }

        @rect.w = Math.max @rect.w, lineProps.w
        @rect.h += lineProps.h

        lineWords = []
        for word in words 
            if word.length > 0
                strObj = new Word word, {
                    x, y, pageIndex
                    w: @doc.widthOfString(word, options)
                    h: @doc.currentLineHeight(no)
                    index: @consumedCharCount
                }
                x += wordSpacing + strObj.w
                @wordData.push strObj
                lineWords.push strObj

            else 
                # end of line, get whitespace from @unconsumedText to keep the index values correct
                word = @unconsumedText.match(/^\s+/) ? ''

            @unconsumedText = @unconsumedText[word.length..]
            @consumedCharCount += word.length

            wordIndex = @wordData.length - 1
            # could optimize this, I'm sure...
            if wordIndex >= 0
                @wordDataIndices.push (wordIndex for char, ii in word)...

        @lines.push new Line lineWords, lineProps

        return this

    ###
    return the rect(s) of each string that matches pattern. Could be two or more rects if the match extends across a line break.
    ###
    getRects: (pattern) ->
        rects = []
        matchCount = 0
        while (results = pattern.exec @originalText)? and (pattern.global or (matchCount++ is 0))
            wordsArr = []
            charIndex = results.index
            matchedText = results[0]

            wordIndex = @wordDataIndices[charIndex]
            matchedLength = 0
            while (matchedLength < matchedText.length)
                word = @wordData[wordIndex++]?.clone()
                break unless word?
                word.offset = charIndex - word.index

                wordsArr.push word
                matchedLength += word.length

            rect = null
            while (matchedText.length > 0) and (wordsArr.length > 0)
                word = wordsArr.shift()
                if (not rect?) or (word.y isnt rect.y)  # new line, make new rect
                    {x, y, h} = word
                    x += @doc.widthOfString word.unusedChars(), @options
                    rect = {x, y, h, w: 0, pageIndex: word.pageIndex}
                    rects.push rect

                rect.w += @doc.widthOfString word[0...(matchedText.length)], @options

                matchedText = matchedText[word.length..].replace /^\s+/, ''

        rects

    annotate: (pattern, args, options) ->
        annotation = @doc[options.Type]
        return unless annotation?

        @doc.saveFont()
        @doc.font @fontSpec.name, @fontSpec.size

        for {x, y, w, h, pageIndex} in @getRects pattern
            @doc.page = @doc.pages[pageIndex] if pageIndex?
            opts = clone options, 'Type'
            annotationArgs = [x, y, w, h].concat(args).concat(opts)
            annotation.apply @doc, annotationArgs

        @doc.restoreFont()

        return this

    highlight: (pattern, args..., options = {}) ->
        options.Type = 'highlight'
        @annotate pattern, args, options

    underline: (pattern, args..., options = {}) ->
        options.Type = 'underline'
        @annotate pattern, args, options

    link: (pattern, args..., options = {}) ->
        options.Type = 'link'
        @annotate pattern, args, options

    strike: (pattern, args..., options = {}) ->
        options.Type = 'strike'
        @annotate pattern, args, options

    rectAnnotation: (pattern, args..., options = {}) ->
        options.Type = 'rectAnnotation'
        @annotate pattern, args, options

module.exports = TextMap

if require.main is module
    PDFDoc = require('./document')
    doc = new PDFDoc
    # doc.scale 1.5 # annotations don't honor transformations
    _w = 1
    until doc.pages.length > 1 
        doc.fontSize 8 + 2*_w
        wid = Math.min _w*100, doc.page.width - doc.page.margins.left - doc.page.margins.right
        y = if _w is 6
            doc.page.height - doc.page.margins.bottom - 2*doc.currentLineHeight() 
        else
            doc.y
        doc.text """
        #{_w}. This is some text that will occupy more than one line with a width of #{wid}. I will underline each group of two or more consonants and strike each group of two or more vowels.
        """, 72, y,
            width: wid
            textMap: yes
        doc.moveDown()

        {textMap} = doc

        # annotate based on regexps
        textMap.highlight(/this .+ line/i)
            .underline(if _w is 6 then /roup of tw/g else /[^aeiou\d\W]{2,}/g)
            .strike(/[aeiou]{2,}/g)

        # textMap has a lines property with an array of broken lines
        # each element of the lines array is an array of words
        # each line and word element has {x, y, w, h} properties
        word = textMap.lines[2].words[3] # get dims of a word of a line of text
        if word?
            {x, y, w, h} = word
            doc.rectAnnotation x-1, y-3, 3+doc.widthOfString("#{word}".replace /\s+/, ''), h+6

        for rect in textMap.rects # the textMap itself also has array of {x, y, w, h} properties
            {x, y, w, h, pageIndex} = rect
            doc.page = doc.pages[pageIndex]
            doc.rect x-2, y-2, w+4, h+4 # draw a rect around the block of text
            doc.moveTo( x + wid, y).lineTo(x + wid, y+h) # the textMap probably isn't exactly as wide as wid
            doc.stroke()
        _w++

    doc.write '/Users/ckirby/Documents/Dropbox/MyGitProjects/out.pdf'

    w = new Word "Hi there"
    console.log w, w.length, w[3..], w.replace(/Hi/, 'Bye'), w.toUpperCase()
    w = new Line ["Hi ", "there"]
    console.log w, w.length, w[3..], w.replace(/Hi/, 'Bye'), w.toUpperCase()

