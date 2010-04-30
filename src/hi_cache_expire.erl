-module(hi_cache_expire).
-author('kode@hover.in').

-export([
	 start/0,
	 loop/2,
	 get/2, get/3,
	 state/0, get_state/0,
	 on_exit/2,
	 stop/0, 
	 send_new_pid_dict/5, key_loop/3,
	 test/0,test/1
	 ]).

start()->
    case erlang:whereis(?MODULE) of
	Pid when is_pid(Pid)->
	    Pid;
	undefined ->
	    Pid = spawn ( fun()->
				  ?MODULE:loop(dict:new(),0)
			  end),

	    case catch erlang:register(?MODULE,Pid) of
		{'EXIT',_}->
		    false;
		_ ->
		    debug({new_mainloop,Pid}),
		    Pid
	    end
    end.

loop(Dict,Ctr)->
    receive
	{get, {From,_}, Now, Key, SetFun, Timeout}->
	    debug({get_start,self(),Key,dict:to_list(Dict),Ctr}),
	    {NewDict,NewCtr} = case dict:find(Key,Dict) of
				   {ok,[{KeyPid,MonRef}=KeyRef]}->
				       debug({search,self(),key_is,Key,keypid_is,KeyPid,self_is,self(),from_is,From}),
				       KeyPid ! {from, {self(),MonRef},From},
				       receive 
					   {KeyPid,_SomeRef,From,SomeBool,SomeData} when is_boolean(SomeBool)->
					       debug({'SEARCH',KeyPid,SomeData}),
					       debug({read,SomeData,dict:to_list(Dict)}),
					       From ! {SomeBool,SomeData},					       
					       {Dict,Ctr};
					   {'DOWN',SomeRef,_,KeyPid,{expire,Key,SomeData}} = SomeDown ->
					       debug({'DOWN_SEARCH',KeyPid,SomeData}),
					       begin erlang:demonitor(SomeRef), erlang:exit(KeyPid,normal) end,
					       debug({'*********down',search,SomeDown}),
					       %% return 'race' instead of 'true', to check how often this happens
					       %% From ! {race, SomeData},	
					       From ! {true, SomeData},
					       TempDict = dict:erase(KeyRef,Dict),
					       debug({'        send exit to ',Now,KeyPid,'data to',From,kill,KeyPid,dict:to_list(TempDict)}),
					       {TempDict,Ctr}
				       end;
				   _E2 ->
				       debug({_E2,self(),write,Key}),
				       {?MODULE:send_new_pid_dict(Dict, From, Key, SetFun, Timeout),Ctr+1}
			       end,
	    %debug({?LINE, state, dict:to_list(NewDict)}),
	    ?MODULE:loop(NewDict,NewCtr);
	debug ->
	    %error_logger:info_msg("state is ~p",[dict:to_list(Dict)]),
	    ?MODULE:loop(Dict,Ctr);
	{debug,From} ->
	    From ! {dict:to_list(Dict),Ctr},
	    ?MODULE:loop(Dict,Ctr);	
	stop ->
	    error_logger:info_msg("state stopped",[]),
	    ?MODULE:loop(dict:new(),0);
	{'EXIT',SomeKeyPid,{expire,SomeKey,_SomeData} }->
	    debug({'*********EXITloopa',self(),'keypid is',SomeKeyPid,dict:to_list(Dict)}),
	    NewDict = dict:erase(SomeKey,Dict),
	    debug({'             loopb',SomeKeyPid,SomeKey, dict:to_list(Dict),to,dict:to_list(NewDict)}),
	    debug({'EXIT',SomeKeyPid,_SomeData}),
	    ?MODULE:loop(NewDict,Ctr-1);
	{'DOWN',_SomeRef,_,SomeKeyPid,{expire,_SomeKey,_SomeData}} = SomeDown ->
	    %begin erlang:demonitor(SomeRef), erlang:exit(SomeKeyPid,kill) end,
	    debug({'*********down',loop,SomeDown,dict:to_list(Dict)}),
	    debug({'         sendloop exit to ',SomeKeyPid}),
	    debug({'DOWN',SomeKeyPid}),	    
	    ?MODULE:loop(Dict,  Ctr);
	_E ->
	    debug({'**********unexpected',else_is,_E,dict:to_list(Dict)}),
	    ?MODULE:loop(Dict,Ctr)
    after 5000 ->
	    debug({"********STATE",self(),dict:to_list(Dict),Ctr,length(erlang:processes())}),
	    ?MODULE:loop(Dict,Ctr)
    end.

send_new_pid_dict(Dict, From, Key, SetFun, Timeout)->
    R = SetFun(Key),
    process_flag(trap_exit,true),
    Pid = spawn_link( fun()->
			 ?MODULE:key_loop( Key, R, Timeout)
		  end),
    MonRef = erlang:monitor(process, Pid),
				
    From ! {false,R},
    dict:store(Key,[{Pid,MonRef}],Dict).

key_loop(Key,Data,Timeout)->
    receive 
	{from,{Reply,MonRef},From} ->
	    Msg =  {self(), MonRef, From, true, Data},
	    Reply ! Msg,
	    %debug({keyloop,send,self(),Msg,to,Reply,from_is,From}),
	    ?MODULE:key_loop(Key, Data, Timeout);
	real_expire ->
	    debug({'*********key_loop',real_expire,self()}),
	    ok;
	Else ->
	    debug({'*********key_loop',else,Else}),
	    ?MODULE:key_loop(Key, Data, Timeout)
    after Timeout ->
	    debug({key_loop,expire,Key,remove,self()}),
	    debug({erlang,processes, length( erlang:processes())}),
	    erlang:exit(self(),{expire,Key,Data}),
	    forcedebug({'*********post_keyloop_fake_expire',self()}),
	    ?MODULE:key_loop(Key, Data, Timeout)
    end.

get(Key,SetFun)->
    ?MODULE:get(Key,SetFun,10000).

get(Key,SetFun,Timeout)->
    MainLoop = ?MODULE:start(),    
    {_,_,Now} = now(),
    debug({get_pre,Now,MainLoop,Key,from_is,self()}),
    MainLoop ! {get,{self(),erlang:make_ref()}, Now, Key, SetFun, Timeout},
    receive 
	Data->
	    debug({get_end,Now,self(),Data}),
	    Data  
    after 5000 ->
	    debug({get_timeout,Key,Now})
    end.
   
debug(_L)->
    %io:format("~n ~p",[_L]).
    ok.
forcedebug(M)-> error_logger:info_msg("~p",[M]).

state()->
    hi_cache_expire ! debug.

get_state()->
    hi_cache_expire ! {debug,self()},
    receive 
	R ->
	    R
    end.

stop()->
    hi_cache_expire ! stop.

on_exit(Pid,Fun)->
    EPid = spawn( fun()->
		   process_flag(trap_exit,true),
		   link(Pid),
		   receive 
		       {'EXIT',Pid,Why}->
			   Fun(Why)
		   end
	   end),
    debug({on_exit,Pid,on_exit,EPid}).

test()->
    test(1).

test(Mul)->
    [ {X*Mul,?MODULE:get(X*Mul,fun(_Z)-> {X*Mul,'data'} end,Y)} || {X,Y} <- 
						 [{10,1000}||_ <- lists:seq(1,2*Mul) ] ++ 
						 [{1,1} ||_ <- lists:seq(1,5) ] ++ 
						 [{10,100} ||_ <- lists:seq(1,3) ] ++
						 [{1,100} ||_ <- lists:seq(1,3*Mul) ] ++
						 [{10,10} ||_ <- lists:seq(1,3) ]
					    ].

