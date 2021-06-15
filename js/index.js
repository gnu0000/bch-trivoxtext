$(function() {
   $.ajax({
      url:     "/trivoxtext.pl?modulelist=1",
      type:    'GET',
      success: function(data){$("#modules").html(data)},
   });
});
