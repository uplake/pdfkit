LineWrapper = require '../styled_line_wrapper'

module.exports =
    styledText: (text, x, y, options) ->
        options = @_initOptions(x, y, options)

        # Convert text to a string
        text = '' + text
                    
        if options.textMap
            @textMap = new PrintedText text, this
        else
            @textMap = null
        
        # if the wordSpacing option is specified, remove multiple consecutive spaces
        if options.wordSpacing
            text = text.replace(/\s{2,}/g, ' ')
            
        paragraphs = text.split '\n'

        # word wrapping
        if options.width
            wrapper = options.wrapper ? new LineWrapper(this)
            wrapper.on 'line', @_line.bind(this)
            wrapper.on 'fragment', @_fragment.bind(this)
            # wrapper.on 'fragment', (args...) -> console.log args[0...3]
            wrapper.wrap(paragraphs, options)
            
        # render paragraphs as single lines
        else
            @_line line, options for line in paragraphs
        
        return this
        
