#!perl
#
# ajax handler for trivoxtext.html
#
# interface: see bottom of file
#
use strict;
use warnings;
use feature 'state';
use CGI qw(:cgi);
use CGI::Carp qw(fatalsToBrowser);
use JSON;
use DBI;
use DBD::mysql;
use List::Util qw(min max);
use Gnu::StringUtil qw(HtmlEncode Trim);
use Gnu::FileUtil qw(SlurpFile);

my $INDEX_ROOT = "d:/projects/tt/data/";


MAIN:
   SaveText     ()            if param("save");
   GetText      ()            if param("childid");
   GetNextRecord()            if defined param("direction");
   GetRecordByID(param("id")) if param("id");
   GetSetList   ()            if param("setlist");
   GetModuleList()            if param("modulelist");
   GenerateIndex()            if param("genindex");
   GetHelp      ();


# updates or creates a new langui, questiontext, or responsetext
# returns the text as text/plain
#
sub SaveText
   {
   my $kind       = param("kind");
   my $id         = param("id");
   my $childid    = param("childid");
   my $text       = param("value");
   my $languageid = param("languageid");
   my $kind       = param("kind");

   Connection($kind);

   if ($childid > 0) # if we have a childid its an update
      {
      my $sql = $kind =~ /uifield/i  ? "update langui       set value=? where id=$childid" :
                $kind =~ /question/i ? "update questiontext set text=?  where id=$childid" :
                $kind =~ /response/i ? "update responsetext set text=?  where id=$childid" :
                                       "";
      UpdateRecord ($sql, $text);
      }
   else  # if we don't have an id its an insert
      {                                
      my $sql = $kind =~ /uifield/i  ? "INSERT INTO langui       (uiId,       langId    , value, adminUserId, confirmed) VALUES (?, ?, ?, 9999, 'NO')" :
                $kind =~ /question/i ? "INSERT INTO questiontext (questionId, languageId, text , adminUserId, current  ) VALUES (?, ?, ?, 9999, 1)"    :
                $kind =~ /response/i ? "INSERT INTO responsetext (responseId, languageId, text , adminUserId, current  ) VALUES (?, ?, ?, 9999, 1)"    :
                                       "";
      UpdateRecord ($sql, $id, $languageid, $text);
      }
   print "Content-type: text/plain\n\n";
   print $text;
   exit(0);
   }

# fetches a langui.value or questiontext.text or responsetext.text
# returns the text as text/plain
#
sub GetText
   {
   my $kind    = param("kind");
   my $childid = param("childid");
   my $table   = TableName($kind, 1);

   Connection($kind);
   my $rec = FetchRow("select * from $table where id=$childid") || {};

   print "Content-type: text/plain\n\n";

   print $kind =~ /uifield/i  ? $rec->{value} :
         $kind =~ /question/i ? $rec->{text}  :
         $kind =~ /response/i ? $rec->{text}  :
                                "";
   exit(0);
   }


# fetches a uifield, question or response record and 2 text kids
#
sub GetRecordByID
   {
   my ($id, %extra) = @_;

   my $kind       = param("kind");
   my $languageid = param("languageid");

   Connection($kind);
   my $rec = {};
   if ($kind =~ /uifield/i)
      {
      $rec            = FetchRow("select * from uifields where id=$id");
      $rec->{english} = FetchRow("select *, value as text from langui where uiId=$id and langId=1804");
      $rec->{foreign} = FetchRow("select *, value as text  from langui where uiId=$id and langId=$languageid");
      }
   if ($kind =~ /question/i)
      {
      $rec            = FetchRow("select * from questions where id=$id");
      $rec->{english} = FetchRow("select * from questiontext where current=1 and questionId=$id and languageId=1804");
      $rec->{foreign} = FetchRow("select * from questiontext where current=1 and questionId=$id and languageId=$languageid");
      }
   if ($kind =~ /response/i)
      {
      $rec            = FetchRow("select * from responses where id=$id");
      $rec->{english} = FetchRow("select * from responsetext where current=1 and responseId=$id and languageId=1804");
      $rec->{foreign} = FetchRow("select * from responsetext where current=1 and responseId=$id and languageId=$languageid");
      }
   $rec = {%{$rec}, %extra};

   print "Content-type: text/json\n\n";
   print to_json($rec);
   exit(0);
   }


sub GetNextRecord
   {
   my $id    = param("id");
   my $dir   = param("direction");

   my $ids   = GetIDs();
   my $count = scalar @{$ids};
   my $pos   = GetIdPosition($id, $ids);

   $pos = max(0, min($count-1, $pos+$dir));
   GetRecordByID($ids->[$pos], _count=>$count, _pos=>$pos);
   }


sub GetIDs
   {
   my @ids;

   my $kind       = param("kind")       || "uifield";
   my $module     = param("module")     || "all";
   my $languageid = param("languageid") || "5912";
   my $missing    = param("missing")    || "0";

   my $filespec   = $INDEX_ROOT . $kind . "_" . $module;
   $filespec .= "_missing_" . $languageid if $missing;
   $filespec .= ".txt";

   open (my $file, "<", $filespec) or _nodata($filespec);
   while (my $id = <$file>)
      {
      chomp $id;
      push @ids, $id;
      }
   close $file;
   return \@ids;
   }

sub _nofile
   {
   my ($filename) = @_;

   print "Content-type: text/json\n\n";
   print to_json({english=>{text=>"$filename"}, foreign=>{text=>"That file wasn't found"}});
   exit(0);
   }

sub _nodata
   {
   my ($filename) = @_;

   print "Content-type: text/json\n\n";
   print to_json
      ({
      id=>0,
      title=>"*No data*",
      _count=>0,
      english=>{id=>0, text=>""}, 
      foreign=>{id=>0, text=>""}
      });
   exit(0);
   }

sub GetIdPosition
   {
   my ($id, $ids) = @_;

   my $ct = scalar @{$ids};
   return 0 unless $ct;

   for (my $i=0; $i<$ct; $i++)
      {
      return $i if $ids->[$i] >= $id;
      }
   return $ids->[$ct-1];
   }


sub TableName
   {
   my ($kind, $ischild) = @_;

   return !$ischild && $kind =~ /uifield/i  ? "uifield"      :
          !$ischild && $kind =~ /question/i ? "question"     :
          !$ischild && $kind =~ /response/i ? "response"     :
          $ischild  && $kind =~ /uifield/i  ? "langui"       :
          $ischild  && $kind =~ /question/i ? "questiontext" :
          $ischild  && $kind =~ /response/i ? "responsetext" :
                                              "";
   }


sub GetSetList
   {
   Connection("question");
   my $sets = FetchArray("select * from sets where firstModuleType='SURVEY' order by name");

   print "Content-type: text/html\n\n";

   print "<ul class='master-links'>\n";
   print "<li><a href='trivoxtext.html?kind=uifield'>All uifield Text</a>  </li>\n";
   print "<li><a href='trivoxtext.html?kind=question'>All Question Text</a></li>\n";
   print "<li><a href='trivoxtext.html?kind=response'>All Response Text</a></li>\n";
   print "</ul>\n";

   print "<table>\n";
   foreach my $set (@{$sets})
      {
      print "<tr>" .
            "<td>$set->{name}</td>" .
            "<td><a href='trivoxtext.html?kind=question&set=$set->{id}'>Question Text</a></td>" .
            "<td><a href='trivoxtext.html?kind=response&set=$set->{id}'>Response Text</a></td>" .
            "</tr>\n";
      }
   print "</table>\n";
   exit(0);
   }


sub GetModuleList
   {
   Connection("question");
   my $modules = FetchArray("select * from modules order by id");

   print "Content-type: text/html\n\n";

   print "<ul class='master-links'>\n";
   print "<li><a href='trivoxtext.html?kind=uifield'>All uifield Text</a>  </li>\n";
   print "<li><a href='trivoxtext.html?kind=question'>All Question Text</a></li>\n";
   print "<li><a href='trivoxtext.html?kind=response'>All Response Text</a></li>\n";
   print "</ul>\n";

   print "<table>\n";
   foreach my $module (@{$modules})
      {
      print "<tr>" .
            "<td>$module->{id}</td>\n" .
            "<td>$module->{name}</td>\n" .
            "<td><a href='trivoxtext.html?kind=question&module=$module->{id}'>Question Text</a></td>" .
            "<td><a href='trivoxtext.html?kind=response&module=$module->{id}'>Response Text</a></td>" .
            "</tr>\n";
      }
   print "</table>\n";
   exit(0);
   }


##############################################################################
#                                                                            #
##############################################################################

# Ok, so....
# Generating the index of questions and responses (or missing questions/responses) 
# for a module is slow because the data is stored as a chain and cannot be 
# queried in one getgo. Since it is too slow to make this list in real-time, 
# we pre-generate the list, and then we load the list in real-time. This
# fn generates the lists files for a single module. This fn is called at page load
#
# cgi params:
#    genindex = 1
#    kind = question or response
#    module = moduleid#
#
sub GenerateIndex
   {
   my $kind = param("kind");

   GenerateUIIndex() if $kind =~ /uifield/i;
   GenerateQRIndex() if $kind =~ /(question)|(response)/i;
   return _done();
   }

sub GenerateUIIndex
   {
   Connection("uifield");

   my $uifields = FetchHash("id"              , "select * from uifields");
   my $languis  = FetchHash(["uiId", "langId"], "select * from langui");
   my ($all, $no5912, $no5265) = ({},{},{});

   foreach my $uifield (values %{$uifields})
      {
      my $id = $uifield->{id};
      $all->{$id} = 1;

      my $langui = $languis->{$id} || {};
      $no5912->{$id} = 1 unless $langui->{5912};
      $no5265->{$id} = 1 unless $langui->{5265};
      }
   Gen("uifield_all.txt"             , $all   );
   Gen("uifield_all_missing_5912.txt", $no5912);
   Gen("uifield_all_missing_5265.txt", $no5265);

   _done();
   }

sub GenerateQRIndex
   {
   my $moduleid = param("module") || return_done();
   return _done() if $moduleid =~ /all/i; # todo ...

   Connection("question");
   my $module = FetchRow("select * from modules where id=$moduleid") || return _done();

   $module->{_questionids}              = {};
   $module->{_questionids_missing_5912} = {};
   $module->{_questionids_missing_5265} = {};
   $module->{_responseids}              = {};
   $module->{_responseids_missing_5912} = {};
   $module->{_responseids_missing_5265} = {};
   $module->{_question_visited}         = {};

   FollowQuestionChain ($module, $module->{firstQuestionId});

   Gen("question_" .$module->{id}. ".txt"             , $module->{_questionids}             );
   Gen("question_" .$module->{id}. "_missing_5912.txt", $module->{_questionids_missing_5912});
   Gen("question_" .$module->{id}. "_missing_5265.txt", $module->{_questionids_missing_5265});

   Gen("response_" .$module->{id}. ".txt"             , $module->{_responseids}             );
   Gen("response_" .$module->{id}. "_missing_5912.txt", $module->{_responseids_missing_5912});
   Gen("response_" .$module->{id}. "_missing_5265.txt", $module->{_responseids_missing_5265});

   _done();
   }

sub _done
   {
   print "Content-type: text/json\n\n";
   print to_json({ok=>1});
   exit(0);
   }


sub Gen
   {
   my ($filename, $hashref) = @_;

   return unless scalar keys %{$hashref};

   my $filespec = $INDEX_ROOT . $filename;
   open (my $file, ">", $filespec);
   map {print $file "$_\n"} sort {$a<=>$b} keys %{$hashref};
   close $file;
   }


sub FollowQuestionChain
   {
   my ($module, $questionid) = @_;

   return unless $module;
   return unless $questionid;

   return if $module->{_question_visited}->{$questionid};
   $module->{_question_visited}->{$questionid} = 1;

   my $moduleid = $module->{id};

   my $question = FetchRow("select * from questions where id=$questionid");
   return unless $question;
   
   CheckQuestionText($module, $question);

   my $qtrms = FetchArray("select * from questiontoresponsemap where questionid=$questionid order by responseNumber");

   foreach my $qtrm (@{$qtrms})
      {
      next unless defined $qtrm->{responseId};

      my $response = FetchRow("select * from responses where id=$qtrm->{responseId}");
      CheckResponseText($module, $question, $response);
      }

   # first, we'll follow questions from the responses
   my %nextQuestionIds = ();
   foreach my $qtrm (@{$qtrms})
      {
      my $flow = FetchRow("select * from flow where questionToResponseMapId=$qtrm->{id} and moduleId=$moduleid");
      $nextQuestionIds{$flow->{targetQuestionId}} = 1 if $flow;
      }
   foreach my $tqid (sort keys %nextQuestionIds)
      {
      FollowQuestionChain($module, $tqid);
      }

   # then we'll follow questions from any logic
   my $logicevaluation = FetchRow("select * from logicevaluations where questionId=$questionid and moduleId=$moduleid");
   FollowQuestionChain($module, $logicevaluation->{targetQuestionId}) if $logicevaluation;

   # finally, we follow child questions
   my $kids = FetchArray ("select * from questionchildren where parentQuestionId=$questionid");
   foreach my $kid (@{$kids})
      {
      FollowQuestionChain($module, $kid->{childQuestionId});
      }
   }


sub CheckQuestionText
   {
   my ($module, $question) = @_;

   return unless $question;
   return if $question->{qtype} =~ /(logic)|(calculation)|(evaluation)/i;

   my $qid  = $question->{id};
   my $qt_e = FetchRow("select * from questiontext where questionId=$qid and languageId=1804 and current=1");
   my $qt_s = FetchRow("select * from questiontext where questionId=$qid and languageId=5912 and current=1");
   my $qt_p = FetchRow("select * from questiontext where questionId=$qid and languageId=5265 and current=1");

   # check: if no english text, its probably not supposed to
   return unless $qt_e;

   $module->{_questionids}->{$qid} = 1;
   $module->{_questionids_missing_5912}->{$qid} = 1 unless $qt_s && Trim($qt_s->{text});
   $module->{_questionids_missing_5265}->{$qid} = 1 unless $qt_p && Trim($qt_p->{text});
   }

sub CheckResponseText
   {
   my ($module, $question, $response) = @_;

   return unless $response;

   my $rid    = $response->{id};
   my $rt_e = FetchRow("select * from responsetext where responseId=$rid and languageId=1804 and current=1");
   my $rt_s = FetchRow("select * from responsetext where responseId=$rid and languageId=5912 and current=1");
   my $rt_p = FetchRow("select * from responsetext where responseId=$rid and languageId=5265 and current=1");

   $module->{_responseids}->{$rid} = 1;
   $module->{_responseids_missing_5912}->{$rid} = 1 unless $rt_s && Trim($rt_s->{text});
   $module->{_responseids_missing_5265}->{$rid} = 1 unless $rt_p && Trim($rt_p->{text});
   }


##############################################################################
#                                                                            #
##############################################################################


sub GetHelp
   {
   print "Content-type: text/html\n\n";
   print <DATA>;

   exit(0);
   }


sub Connection
   {
   my ($kind) = @_;

   state $db;
   $db = Connect($kind) if $kind;
   return $db;
   }

sub Connect
   {
   my ($kind)  = @_;

   my $database = $kind =~ /uifield/i ? "onlineadvocate" : "questionnaires";
   return DBI->connect("DBI:mysql:host=localhost;database=$database;user=advocate;password=purelyponddevice") or die "cant connect to $database";
   }

sub FetchArray
   {
   my ($sql) = @_;

   my $db = Connection();
   my $sth = $db->prepare ($sql) or return undef;
   $sth->execute ();
   my $results = $sth->fetchall_arrayref({});
   $sth->finish();
   return $results;
   }

sub FetchHash
   {
   my ($key, $sql) = @_;

   my $db = Connection();
   my $sth = $db->prepare ($sql) or return undef;
   $sth->execute ();
   my $results = $sth->fetchall_hashref($key);
   $sth->finish();
   return $results;
   }


sub FetchRow
   {
   my ($sql, @params) = @_;

   my $db = Connection();
   my $results = $db->selectrow_hashref($sql);
   return $results;
   }


sub UpdateRecord
   {
   my ($sql, @bindparams) = @_;

   my $db = Connection();
   my $sth = $db->prepare ($sql) or return undef;
   $sth->execute (@bindparams) or die $sth->errstr;
   $sth->finish();
   }

__DATA__

<html>
   <body>
      <h2>Interface:</h2>

      <h3>Get a parent record with 2 child records (json):</h3>
      <p>This fetches by the id of the parent record</p>
      <pre>
       GET
         kind       = uifield|question|response
         id         = 999
         languageid = 5912
      </pre>
      <a href='trivoxtext.pl?kind=uifield&id=1&languageid=5912'>UiField example</a>
      <a href='trivoxtext.pl?kind=question&id=1&languageid=5912'>Question example</a>
      <a href='trivoxtext.pl?kind=response&id=1&languageid=5912'>Response example</a>

      <h3>Get a parent record with 2 child records (json):</h3>
      <p>This fetches the next/prev record</p>
      <pre>
       GET
         kind       = uifield | question | response
         id         = 999
         direction  = 1 | -1 | 10 | -10 etc...
         set        = all | setid
         languageid = 5912
      </pre>
      <a href='trivoxtext.pl?kind=uifield&id=1&direction=1&set=all&languageid=5912'>UiField example</a>
      <a href='trivoxtext.pl?kind=question&id=1&direction=1&set=all&languageid=5912'>Question example</a>
      <a href='trivoxtext.pl?kind=response&id=1&direction=1&set=all&languageid=5912'>Response example</a>

      <h3>Get a specific langui/questiontext/responsetext string (text)</h3>
      <p>This fetches by the id of the child record</p>
      <pre>
       GET
         kind       = uifield|question|response
         childid    = 999
      </pre>
      <a href='trivoxtext.pl?kind=uifield&childid=1'>UiField example</a>
      <a href='trivoxtext.pl?kind=question&childid=1'>Question example</a>
      <a href='trivoxtext.pl?kind=response&childid=1'>Response example</a>

   
      <h3>Save a specific langui/questiontext/responsetext record</h3>
      <p>This updates/creates a child record</p>
      <pre>
       POST
         kind       = uifield|question|response
         id         = 999
         childid    = 999
         value      = text
         save       = 1
         languageid = 5912
      </pre>
   </body>
</html>
