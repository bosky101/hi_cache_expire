# where do we use this cache ?
hi_cache_expire is only worried about peformance for the most used values used in your webapp. You can easily designate user or your own config by using a bucket, then have subkey's called key's common in many two-dimensional datastores. So regardless of where your data is coming from, if you want it fast & predominantly use erlang for serving content/data, then hi_cache_expire is for you.

At hover.in, hi_cache_expire is used to bypass the backend like most cache's. the one extra feature is that unlike most cache's the data is stored in-memory when used within the expire seconds. When there is no call for the past N seconds, it is removed from memory. but when it's used continously it's always stored in-memory. ( great to also find how many active key's are involved at any point of time for a bucket )

# how do you use it ?
  There is only one call used. it's a get that set's incase data isnt in memory.

  hi_cache_expire:get ( Bucket:<term>, key:<term> , Fun:<function>, Expire:<integer> )
  
  eg: 
	hi_cache_worker:get(
	"recentsearchresults",
 	"bosky101", 
	fun([X)-> 
		X = mnesia_wrapper:dirty_read({emp,X}), 
		Y = some_other_nosql_backend(X),
		X + Y
	 end,
	600
	)

# what does it return
{true, Data} means that Data was cached
{false, Data} means that this data wasnt in-memory and called within a window of Expire seconds. Hence it needs to be queried again. Data will be removed from memory after Expire seconds of inactivity. See test functions, and enable debug to debug, dig deeper.

# where all do you use it ?
If you're an ad network or widget company, your data needs to be delivered from your user's pages asap. We've practiacally abstracted all db calls from high-traffic scenario's. Works well on a cluster as well. Great for saving up constucted json binaries. When the traffic subsides, the process will die.

# secret sauce ?
Processe's return {true,Data}, {false,Data}. There is another debug state of {rae,Data}. Processe's can die at two stages. A race condition occurs when a request is started, the process dies since it was supposed to after N seconds. In this case the data is reconstucted. There is also a possibility that a process dies when no request has started. These go un-noticed since there is no request for them and sort of garbage collected by hi_cache_expire. to see when the race condition occurs uncomment the line that returns {false, Data } instead of {race,Data}

# feedback & bugs ?
mail kode at hover dot in, visit http://developers.hover.in or follow @bosky101
