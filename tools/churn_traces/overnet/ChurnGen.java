import java.io.BufferedReader;
import java.io.FileNotFoundException;
import java.io.FileReader;
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.util.HashMap;
import java.util.Set;
import java.util.StringTokenizer;
import java.util.Vector;

public class ChurnGen {

	static final String help =
		"Usage : java -Xmx2000m [--help] [-h/-m/-s int] [-f string] [-n int] [--startnum int]" +
		"\n\t--help\t\tDisplay this help" +
		"\n\t-h/-m/-s\t\tAdd hours/minutes/seconds to total time" +
		"\n\t-f\t\tSet input file" +
		"\n\t-n\t\tSet number of nodes" +
		"\n\t--startnum\t\tStart numeroting node from ... (default 1)" +
		"\n\t--simulation\t\tType of output is a single file (default)" +
		"\n\t--separate\t\tType of output is separate files"+
		"\n\t--splay\t\t\tOutput is compatible with Splay churn module";

	static int num = -1 ;
	static int maxU = -1 ;
	static HashMap<Integer,Integer> timestamps = new HashMap<Integer,Integer>();
	static HashMap<Integer,HashMap<String,Boolean> > avail
	= new HashMap<Integer,HashMap<String,Boolean> >();
	static HashMap<String,Integer> updates = new HashMap<String,Integer>();

	// parameters
	static String filename = null ; 
	static int time = 0 ;
	static int nodes = 0 ;
	static int startnum = 1 ;
	static boolean outputAsSeparateFiles = false ; // default : one single file
 	static boolean splayFormat = false ; // compatibility with splay churn 

	private static void parseArgs(String[] args) {
		//		 parse args
		int curArg = 0;
		if (args.length < 3 ) {
			System.out.println(help);
			System.exit(0);
		}
		while (curArg < args.length) {
			if (args[curArg].equalsIgnoreCase("--help")) {
				// display help
				System.out.println(help);
				System.exit(0);
			} else if (args[curArg].equalsIgnoreCase("-h")) {
				curArg ++ ;
				if (curArg == args.length) {
					System.out.println("int missing");
					System.exit(1);
				}
				time += Integer.parseInt(args[curArg]) * 60 * 60 ;
			} else if (args[curArg].equalsIgnoreCase("-m")) {
				curArg ++ ;
				if (curArg == args.length) {
					System.out.println("int missing");
					System.exit(1);
				}
				time += Integer.parseInt(args[curArg]) * 60  ;
			} else if (args[curArg].equalsIgnoreCase("-s")) {
				curArg ++ ;
				if (curArg == args.length) {
					System.out.println("int missing");
					System.exit(1);
				}
				time += Integer.parseInt(args[curArg])  ;
			} else if (args[curArg].equalsIgnoreCase("-n")) {
				curArg ++ ;
				if (curArg == args.length) {
					System.out.println("int missing");
					System.exit(1);
				}
				nodes = Integer.parseInt(args[curArg]) ;
			} else if (args[curArg].equalsIgnoreCase("--startnum")) {
				curArg ++ ;
				if (curArg == args.length) {
					System.out.println("int missing");
					System.exit(1);
				}
				startnum = Integer.parseInt(args[curArg]) ;
			} else if (args[curArg].equalsIgnoreCase("-f")) {
				curArg ++ ;
				if (curArg == args.length) {
					System.out.println("filename missing");
					System.exit(1);
				}
				filename = args[curArg] ;
			} else if (args[curArg].equalsIgnoreCase("--simulation")) {
				outputAsSeparateFiles = false ;
			} else if (args[curArg].equalsIgnoreCase("--separate")) {
				outputAsSeparateFiles = true ;
			} else if (args[curArg].equalsIgnoreCase("--splay")) {
				splayFormat = true ;
			}
			curArg ++ ;
		}
		if (time == 0 || nodes == 0) {
			System.err.println("Error: nodes or time not defined.");
			System.exit(1);
		}
	}
	
	public static void main(String[] args) {
		parseArgs(args);		

		int lineread = 0 ;
		// step 1 : open and read the file
		BufferedReader in;
		System.out.print("Reading input: ");
		try {
			in = new BufferedReader (new FileReader(filename));
			String current ;
			current = in.readLine() ;
			while (current != null) {
				StringTokenizer st = new StringTokenizer(current);
				if (current.equalsIgnoreCase("")) { 
				} else if (st.countTokens() == 5) {
					updateTimestamp(st);
				} else if (st.countTokens() == 3) {
					updateAvailability(st);
				} else {
					System.err.println("unconsistent data");
				}
				++lineread;
				if (lineread %100000 == 0) {
					System.out.print("#");
				}
				current = in.readLine() ;
			}
		} catch (FileNotFoundException e) {
			e.printStackTrace();
			System.exit(1);
		} catch (IOException e) {
			e.printStackTrace();
			System.exit(1);
		}
		System.out.println();

		System.out.print("Removing uncomplete data ...");
		// filter uncomplete one
		int removed = 0 ;
		
		Vector<String> toRemove = new Vector<String>();
		System.out.println("avail(0).keySet().size() = "+avail.get(50).keySet().size()+" ; maxu = "+maxU);
		for (String s : avail.get(50).keySet()) {
			if (updates.get(s) < maxU) {
				toRemove.add(s);
				removed++;
			}
		}
		for (String s : toRemove) {
			for (int i : avail.keySet()) {
				avail.get(i).remove(s);
			}
		}

		System.out.print("ok ; removed "+removed+" ; remains "+avail.get(0).size()+"\n");
		
		// filter nodes that are always offline
		toRemove.clear();
		int basetime = timestamps.get(0);
		for (String s : avail.get(0).keySet() ) {
			boolean alwaysOffline = true ;
			for (int p : avail.keySet()) {
				//System.out.println("p = "+p+" and time = "+time+" and timestamps.get(p) - basetime ="+(timestamps.get(p)-basetime));
				if (timestamps.get(p)-basetime > time) {
					continue ;
				} else if (avail.get(p).get(s)) {
					alwaysOffline = false ;
				}
			}
			if (alwaysOffline) {
				toRemove.add(s);
			}
		}
		for (String s : toRemove) {
			for (int i : avail.keySet()) {
				avail.get(i).remove(s);
			}
		}
		System.out.println("Removed "+toRemove.size()+" nodes that are always offline during allowed time period.");
		
		// generate churn informations
		System.out.println("Generating churn");
		generateChurn();
		System.out.println("done.");
	}

	public static void updateTimestamp (StringTokenizer st) {
		num ++ ;
		try {
			st.nextToken(); st.nextToken(); st.nextToken();st.nextToken();
		} catch (Exception e) {
			System.err.println("oups");
			System.exit(1);
		}
		String next = st.nextToken();
		//System.out.println("next ="+ next);
		int timestamp = Integer.parseInt(next);
		timestamps.put(num, timestamp);
	}

	public static void updateAvailability(StringTokenizer st) {
		String cle = st.nextToken();
		st.nextToken();
		String val = st.nextToken() ;
		if (! avail.containsKey(num)) {
			// create hashmap
			avail.put(num, new HashMap<String,Boolean>());
		}
		HashMap<String, Boolean> current = avail.get(num);
		current.put(cle, (val.equalsIgnoreCase("1")));

		if (updates.containsKey(cle)) {
			int c = updates.get(cle);
			c++;
			updates.put(cle, c);
			if (c > maxU) {
				maxU = c ;
			}
		} else {
			updates.put(cle,1);
		}
	}

	public static void generateChurn () {
		// generate times
		boolean cont = true ;
		Vector<Integer> times = new Vector<Integer>();
		int j = 0;
		// take basetime
		int basetime = timestamps.get(0);
		int bonustime = 0 ;
		
		System.out.print("-> generating timestamps: ");
		while (cont) {
			// take timestamp at j
			int t = timestamps.get(j);
			t -= basetime ;
			// add bonus
			t += bonustime ;
			// add time (no randomization)
			times.add(t);
			if (t <= time) {
				if (j == timestamps.size()-1) {
					// add bonus
					bonustime += times.get(j);
					bonustime += (timestamps.get(j) - timestamps.get(j-1));
					j = -1 ;
				}
				j++;
			} else {
				// enough already
				cont = false ;
			}
		}
		System.out.println("done.");
		
		// take the set of nodes
		String[] originNodes = new String[avail.get(0).size()];
		Set<String> nn = avail.get(0).keySet() ;
		int toto = 0 ;
		for (String s : nn) {
			originNodes[toto] = s ;
			toto++;
		}
		
		j = 0 ;
		int currentNode = 0 ;
		System.out.print("-> generating churn models (# = 100 nodes generated): ");
		for (int i = 0 ; i < nodes; i++) {
			if (j == originNodes.length) {
				j = 0 ;
			}
			if (outputAsSeparateFiles) {
				outputChurnModelSeparate(currentNode, originNodes[j],times);
			} else {
				outputChurnModelSingle(currentNode, originNodes[j],times);
			}
			
			currentNode ++ ;
			if (currentNode % 100 == 0) {
				System.out.print("#");
			}
			j++ ;
		}
		System.out.println("");
		
		// close single output file
		if (!outputAsSeparateFiles) {
			if (outputSingle != null) {
				try {
					outputSingle.flush();
					outputSingle.close();
				} catch (IOException e) {
					System.err.println("Can't close output file !");
					e.printStackTrace();
				}
				
			}
		}
	}

	static FileWriter outputSingle = null ;
	public static void outputChurnModelSingle (int numNode, String origin, Vector<Integer> times) {
		// state is "down" by default
		boolean state = false ;
		
		try {
			if (outputSingle == null) {
				// create output filewriter
				File dir= new File("results/");
				dir.mkdir();
				if (splayFormat==true) {
					outputSingle = new FileWriter("results/churn_all_splay.churn");
				} else
					outputSingle = new FileWriter("results/churn_all.churn");
				System.out.println("Writing results to churn_all.churn");
			}
			
			int j = 0 ; // index in avail map : cycle through nodes as many times as needed
			
			if (splayFormat == true ) {
					String node_life="";
					for (int i = 0 ; i < times.size(); i++) {
						if (j == avail.size()) j = 0 ;

						//System.out.println("debug: j="+j+" ; origin="+origin+" i="+i+" avail has j:"+avail.containsKey(j));
						boolean periodState = avail.get(j).get(origin);

						if (!state && periodState) {
							//System.out.println("going up");
							int t ;
							if (i != times.size() - 1) {
								t = times.get(i) + ((int)(Math.random()*(times.get(i+1)-times.get(i))));
							} else {
								// end of flow
								t = times.get(i);
							}
							//outputSingle.write(t+"\t"+"U\n");
							node_life=node_life+" "+t;
							state = true ;
						} else if (state && !periodState) {
							//System.out.println("going down");
							int t ;
							if (i != times.size() - 1) {
								t = times.get(i) + ((int)(Math.random()*(times.get(i+1)-times.get(i))));
							} else {
								// end of flow
								t = times.get(i);
							}
							//outputSingle.write(t+"\t"+"D\n");
							node_life=node_life+" "+t;
							state = false ;
						}
						j++;
					}
					outputSingle.write(node_life+"\n");
			} else{			
			
			// output the number of the node
			outputSingle.write("node "+(startnum+numNode)+"\n");
			
			for (int i = 0 ; i < times.size(); i++) {
				if (j == avail.size()) j = 0 ;
				
				//System.out.println("debug: j="+j+" ; origin="+origin+" i="+i+" avail has j:"+avail.containsKey(j));
				boolean periodState = avail.get(j).get(origin);
				
				if (!state && periodState) {
					//System.out.println("going up");
					int t ;
					if (i != times.size() - 1) {
						t = times.get(i) + ((int)(Math.random()*(times.get(i+1)-times.get(i))));
					} else {
						// end of flow
						t = times.get(i);
					}
					outputSingle.write(t+"\t"+"U\n");
					state = true ;
				} else if (state && !periodState) {
					//System.out.println("going down");
					int t ;
					if (i != times.size() - 1) {
						t = times.get(i) + ((int)(Math.random()*(times.get(i+1)-times.get(i))));
					} else {
						// end of flow
						t = times.get(i);
					}
					outputSingle.write(t+"\t"+"D\n");
					state = false ;
				}
				j++;
			}
			outputSingle.write("0 F\n");
			}
		} catch (Exception e) {
			e.printStackTrace();
			System.err.println("Arggh ... can't write "+ "results/node_"+numNode+".churn");
			System.exit(1);
		}
	}
	
	public static void outputChurnModelSeparate (int numNode, String origin, Vector<Integer> times) {
		// state is "down" by default
		boolean state = false ;
		
		try {
			File dir= new File("results/");
			dir.mkdir();
			FileWriter output = new FileWriter("results/node_"+(startnum+numNode)+".churn");
			System.out.println("... writing "+"results/node_"+(startnum+numNode)+".churn");
			
			int j = 0 ; // index in avail map : cycle through nodes as many times as needed
			for (int i = 0 ; i < times.size(); i++) {
				if (j == avail.size()) j = 0 ;
				
				//System.out.println("debug: j="+j+" ; origin="+origin+" i="+i+" avail has j:"+avail.containsKey(j));
				boolean periodState = avail.get(j).get(origin);
				
				if (!state && periodState) {
					//System.out.println("going up");
					int t ;
					if (i != times.size() - 1) {
						t = times.get(i) + ((int)(Math.random()*(times.get(i+1)-times.get(i))));
					} else {
						// end of flow
						t = times.get(i);
					}
					output.write(t+"\t"+"U\n");
					state = true ;
				} else if (state && !periodState) {
					//System.out.println("going down");
					int t ;
					if (i != times.size() - 1) {
						t = times.get(i) + ((int)(Math.random()*(times.get(i+1)-times.get(i))));
					} else {
						// end of flow
						t = times.get(i);
					}
					output.write(t+"\t"+"D\n");
					state = false ;
				}
				j++;
			}
			output.flush();
			output.close();
		} catch (Exception e) {
			e.printStackTrace();
			System.err.println("Arggh ... can't write "+ "results/node_"+(startnum+numNode)+".churn");
			System.exit(1);
		}
	}
}
