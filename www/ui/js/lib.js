/*!
 * PGXN JavaScript Library
 * http://pgxn.org/
 *
 * Copyright 2010, David E. Wheeler. Some Rights Reserved.
 *
 */

PGXN = {
    init_moderate: function () {
        $(document).ready(function() {
            $('.userplay').click(function (e) {
                var bub = $(this).next().first();
                $(bub).css({
                    position:'absolute',
                    left:$(this).offset().left - 20,
                    top:$(this).offset().top + 31
                }).toggle();
                $(bub).click(function () { $(this).hide() });
                e.stopPropagation();
            });

            $('.actions .accept, .actions .reject').click(function (e) {
                e.preventDefault();
                var tr = $(this).parents('tr');
                $.ajax({
                    url: this.href,
                    dataType: 'html',
                    beforeSend: function() {
				        tr.children().animate({'backgroundColor':'#fb6c6c'}, 300);
			        },
                    success: function () {
                        tr.fadeOut(500, function() { tr.remove(); });
                    },
                    error: function (xhr) {
                        var err = jQuery(xhr.responseText);
                        err.hide();
                        $('#userlist').before(err);
                        err.fadeIn(500);
                    }
                });
            });

        });
    },

    validate_form: function(form) {
        $(document).ready(function() {
            $(form).validate({
                errorClass: 'invalid',
                wrapper: 'div',
                highlight: function(e) {
                    $(e).addClass('highlight');
                    $(e.form).find('label[for=' + e.id + ']').addClass('highlight');
                },
                unhighlight: function(e) {
                    $(e).removeClass('highlight');
                    $(e.form).find('label[for=' + e.id + ']').removeClass('highlight');
                },
                errorPlacement: function (er, el) { $(el).before(er) }
            });
        });
    }
};


 