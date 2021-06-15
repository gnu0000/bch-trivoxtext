
$(function() {
   var app = new TTHandler();
});


function TTHandler() {
   var self = this;

   this.Init = function() {
      self.InitAttributes();
      self.InitEvents();
      self.InitState();
   }

   this.InitAttributes = function() {
      self.ajaxurl         = "/trivoxtext.pl";
      self.englishBox      = $(".edit.english");
      self.foreignBox      = $(".edit.foreign");
      self.englishRTId     = $(".english-qtid");
      self.foreignRTId     = $(".foreign-qtid");
      self.idInput         = $(".id-input"    );
      self.itemName        = $("#text-name"   );
      self.count           = $("#count"       );
      self.spinner         = $("#spinner"     );
      self.prevButton      = $(".prev"        );
      self.nextButton      = $(".next"        );
      self.xprevButton     = $(".xprev"       );
      self.xnextButton     = $(".xnext"       );
      self.xxprevButton    = $(".xxprev"      );
      self.xxnextButton    = $(".xxnext"      );
      self.firstButton     = $(".first"       );
      self.lastButton      = $(".last"        );
      self.languageSelect  = $("#language"    );
      self.missingCheck    = $("#missing"     );

      self.englishLanguage = 1804;
      self.foreignLanguage = self.UrlParam("language", 5912);
      self.kind            = self.UrlParam("kind"    , "uifield");
      self.module          = self.UrlParam("module"  , "all");
      self.searchId        = self.UrlParam("id"      , 0);
      self.searchMinLength = 1;
   };

   this.InitEvents = function() {
      self.englishBox.editable(self.ajaxurl, { 
         loadurl   : self.ajaxurl,
         indicator : "<img src='/images/loading.gif'>",
         type      : "textarea",
         id        : "childid", 
         submit    : "OK",
         cancel    : "Cancel",
         tooltip   : "Click to edit...",
         submitdata: self.EnglishSubmitData,
         loaddata  : self.LoadData
      });

      self.foreignBox.editable(self.ajaxurl, { 
         loadurl   : self.ajaxurl,
         indicator : "<img src='/images/loading.gif'>",
         type      : "textarea",
         id        : "childid", 
         submit    : "OK",
         cancel    : "Cancel",
         tooltip   : "Click to edit...",
         submitdata: self.ForeignSubmitData,
         loaddata  : self.LoadData
      });

      self.idInput.change(self.IdChanged).keyup(self.IdChanged);
      self.languageSelect.change(self.languageChanged);
      self.missingCheck.change(self.missingChanged);
      self.prevButton.click(function()  {self.Next(-1)});
      self.nextButton.click(function()  {self.Next(1)});
      self.xprevButton.click(function() {self.Next(-10)});
      self.xnextButton.click(function() {self.Next(10)});
      self.xxprevButton.click(function(){self.Next(-100)});
      self.xxnextButton.click(function(){self.Next(100)});
      self.firstButton.click(function() {self.Next(-9999)});
      self.lastButton.click(function()  {self.Next(9999)});

   };

   this.InitState = function() {
      $(".kind").text(self.kind);
      self.GenerateIndex();
   };

   this.EnglishSubmitData = function () {
      return {
         kind:       self.kind,
         id:         self.idInput.val(),
         childid:    self.englishRTId.text(),
         save:       1, 
         languageid: self.englishLanguage
      };
   };

   this.ForeignSubmitData = function () {
      return {
         kind:       self.kind,
         id:         self.idInput.val(),
         childid:    self.foreignRTId.text(),
         save:       1, 
         languageid: self.foreignLanguage
      };
   };

   this.LoadData = function () {
      return {kind: self.kind};
   };

   this.IdChanged = function (e) {
      var input = $(this);
      var text = input.val();

      if (text.length >= self.searchMinLength) {
         window.setTimeout(function () {self.HandleSearch(text, input)}, self.searchDelay);
      }
   };

   this.languageChanged = function () {
      self.foreignLanguage = self.languageSelect.val();
      self.idInput.val(0)
      self.Next(0);
   };

   this.missingChanged = function () {
      self.idInput.val(0)
      self.Next(0);
   };

   this.HandleSearch = function (text, input) {
      if (input.val() === text && text !== self.lastSearch) {
         self.lastSearch = text;
         self.Search(text);
      }
   };

   this.Search = function (text) {
      self.searchId++;

      $.ajax({
         url:     self.ajaxurl,
         data:    {kind:self.kind, id:text, languageid:self.foreignLanguage},
         type:    'GET',
         success: function(data){self.Update(data, self.searchId)},
      });

   };

   this.Next = function (direction) {
      self.searchId++;

      var ajaxdata = {
         kind:       self.kind, 
         module:     self.module,
         missing:    (self.missingCheck.is(":checked") ? 1 : 0),
         id:         self.idInput.val(), 
         direction:  direction,
         languageid: self.foreignLanguage
      };
      $.ajax({
         url:     self.ajaxurl,
         data:    ajaxdata,
         type:    'GET',
         success: function(data){self.Update(data, self.searchId)},
      });
   };

   this.Update = function (data, searchId) {
      if (searchId < self.doneSearchId) // ignore older search results
         return;
      self.doneSearchId = searchId;

      if (!data)
         return;

      var eqtid = (data && data.english) ? data.english.id   : "0000";
      var etext = (data && data.english) ? data.english.text : "";

      var fqtid = (data && data.foreign) ? data.foreign.id   : "0000";
      var ftext = (data && data.foreign) ? data.foreign.text : "";

      self.idInput.val(data.id);
      self.englishRTId.html(eqtid);
      self.foreignRTId.html(fqtid);

      self.englishBox.html (etext);
      self.foreignBox.html (ftext);

      self.englishBox.attr("id", eqtid);
      self.foreignBox.attr("id", fqtid);

      self.itemName.text(data.itemName ? data.itemName : data.title);

      self.count.text(data._count);

   };

   this.GenerateIndex = function() {
      self.ShowSpinner(1);
      $.ajax({
         url:      self.ajaxurl,
         data:     {kind:self.kind, genindex:1, module:self.module},
         type:     'GET',
         complete: self.IndexComplete
      });
   };

   this.IndexComplete = function() {
      self.ShowSpinner(0);
      self.Next(0);
   };

   this.ShowSpinner = function(bShow) {
      if (bShow)  self.spinner.show();
      if (!bShow) self.spinner.hide();   
   };


   this.UrlParam = function (name, defaultVal) {
      var results = new RegExp('[\\?&]' + name + '=([^&#]*)').exec(window.location.href);
      if(results)
         return decodeURIComponent(results[1]);
      else
         return defaultVal;
   };

   this.Init();
}
