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

        @fontSpec = @currentFontSpec()

    currentFontSpec: -> {name: @doc._font.filename, size: @doc._fontSize}

    saveFont: ->
        @doc._fontStack.push @currentFontSpec()
        return this
        
    restoreFont: ->
        fontSpec = @doc._fontStack.pop() or {name: 'Helvetica', size: 12}
        @doc.font fontSpec.name, fontSpec.size


    initRect: ->
        @rect = 
            x: Infinity
            y: Infinity
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

        @saveFont()
        @doc.font @fontSpec.name, @fontSpec.size

        for {x, y, w, h, pageIndex} in @getRects pattern
            @doc.page = @doc.pages[pageIndex] if pageIndex?
            opts = clone options, 'Type'
            annotationArgs = [x, y, w, h].concat(args).concat(opts)
            annotation.apply @doc, annotationArgs

        @restoreFont()

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

