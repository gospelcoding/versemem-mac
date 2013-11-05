require 'sqlite3'
require 'date'

def get_input(prompt)
  print prompt + '>'
  return $stdin.gets.chomp
end

def get_db
  db = SQLite3::Database.new('/Users/rick/dev/versemem-mac/dbversemem.db')
  db.type_translation = true
  db.results_as_hash = true
  return db
end

def get_user(username, db)
  user = db.get_first_row("SELECT * FROM USERS WHERE name=?", username)
  unless user
    username = get_input("User #{username} does not exist!\n User")
    user = get_user(username)
  end
  return user
end

def help
  puts "vmem new: Add a new verse/passage to memorize"
  puts "vmem quiz (username): Quiz yourself on a verse. If a username is not supplied, it will be prompted for."
  puts "vmem list (username): List verses along with their status and percentage by that user."
  puts "vmem add user (username): Add a new user to the database."
end

def new_verse_record(verse, user, db)
  #arbitrarily set last_attempt to 3 days ago so it has a value
  db.execute("INSERT INTO verse_records (verse_id, user_id, status, right, wrong, streak, streak_type, last_attempt)
              VALUES (?, ?, 'learning', 0, 0, 0, 'wrong', ?)", 
              verse['v_id'], user['u_id'], (Date.today - 3).to_s)
end

def add_user()
  if(ARGV[2])
    username = ARGV[2]
  else
    username = get_input('Username')
  end
  
  db = get_db
  db.execute("INSERT INTO users (name) VALUES (?)", username)
  user = db.execute("SELECT * FROM users WHERE name=?", username)
  verses = db.execute("SELECT * FROM verses")
  verses.each do |verse|
    new_verse_record(verse, user, db)
  end
end

def new_verse()
  reference = get_input("Reference? (eg 'John 3:16')")
  body = get_input("Type in the verse/passage")
  
  db = get_db()
  db.execute("INSERT INTO verses (reference, body)
              VALUES(?, ?)", reference, body)
  verse = db.get_first_row("SELECT * FROM verses ORDER BY v_id DESC")
  users = db.execute("SELECT * FROM users")
  users.each do |user|
    new_verse_record(verse, user, db)
  end
end

def print_record(record)
  streak_text = ''
  streak_text = ", #{record['streak']} in a row" if record['streak_type'] == 'right'
  puts "#{record['reference']} - #{record['status']} #{record['right']}/#{record['right']+record['wrong']} #{streak_text}"
end

def list(username=nil)
  if username  
    #already set no need to act
  elsif(ARGV[1])
    username = ARGV[1]
  else
    username = get_input('Username')
  end
  
  db = get_db()
  user = get_user(username, db)
  verse_records = db.execute("SELECT * FROM verses INNER JOIN verse_records 
                              ON verses.v_id=verse_records.verse_id 
                              WHERE verse_records.user_id=?", user['u_id'])
  verse_records.each do |record|
    print_record(record)
  end
end

def randopick(options, weights, normalized=false)
  unless normalized
    sum = 0
    weights.each{|w| sum += w}
    weights.each_index do |i|
      weights[i] = weights[i].to_f/sum
    end
  end
  
  r = rand()
  sum = 0
  choice = nil
  options.each_index do |i|
    sum += weights[i]
    choice = options[i] if r < sum && choice==nil
  end
  puts "Randopick fail: r=#{r} weights=#{weights} options=#{options}" unless choice
  return choice
end

def select_verse(user, db)
  status_options = ['learning', 'refreshing', 'mastered']
  status_weights = [0.5, 0.3, 0.2]
  verse_options = []
  while(verse_options.empty?)
    status = randopick(status_options, status_weights, true)
  
    verse_options = db.execute("SELECT * FROM verses INNER JOIN verse_records
                                ON verses.v_id=verse_records.verse_id
                                WHERE verse_records.status=? AND verse_records.user_id=?",
                                status, user['u_id'])
  end
  verse_weights = []
  verse_options.each do |verse|
    verse_weights << (Date.today - Date.parse(verse['last_attempt'])).to_i + 1
  end
  return randopick(verse_options, verse_weights, false)
end

def check_answer(body, attempt)
  body_array = body.split
  attempt_array = attempt.split
  attempt_i = 0
  body_i = 0
  while(body_i < body_array.size && attempt_i < attempt_array.size)
    bword = body_array[body_i].downcase.gsub(/[^a-z]/, '')  #downcase and pull everything not a letter
    aword = attempt_array[attempt_i].downcase.gsub(/[^a-z]/, '')
    #puts bword + '   ' + aword
    if(bword.empty?)
      body_i += 1  #skip this word in body and move on
    elsif(aword.empty?)
      attempt_i += 1 #skip this word in attempt and move on
    elsif(bword == aword) #match
      body_i += 1
      attempt_i += 1
    else  #mismatch
      puts "\nTry again:"
      return body_array[0..body_i].join(' ')
    end
  end
  if body_i < body_array.size
    puts "\nTry again!"
    return body_array[0..body_i].join(' ')
  end
  puts "\nGood!"
  puts ''
  return ''
end

def update_verse_record(verse_record, success, db)
  if success
    verse_record['right'] += 1
    if verse_record['streak_type']=='right'
      verse_record['streak'] += 1
    else
      verse_record['streak_type'] = 'right'
      verse_record['streak'] = 1
    end
    case verse_record['status']
    when 'refreshing'
      verse_record['status'] = 'mastered' if verse_record['streak'] >= 3
    when 'learning'
      if verse_record['streak'] >= 7
        verse_record['status'] = 'refreshing'
        verse_record['streak'] = 0
      end
    end
    
  else #failure
    verse_record['wrong'] += 1
    if verse_record['streak_type'] == 'wrong'
      verse_record['streak'] += 1
    else
      verse_record['streak_type'] = 'wrong'
      verse_record['streak'] = 1
    end
    case verse_record['status']
    when 'refreshing'
      verse_record['status'] = 'learning' if verse_record['streak'] >= 3
    when 'mastered'
      verse_record['status'] = 'refreshing'
      verse_record['streak'] = 0
    end
  end
  db.execute("UPDATE verse_records SET streak=?, streak_type=?, right=?, wrong=?, status=?, last_attempt=?
              WHERE vr_id=?",
              verse_record['streak'], verse_record['streak_type'], verse_record['right'],
              verse_record['wrong'], verse_record['status'], Date.today.to_s, verse_record['vr_id'])
end

def quiz
  if(ARGV[1])
    username = ARGV[1]
  else
    username = get_input('Username')
  end
  
  db = get_db()
  user = get_user(username, db)
  verse = select_verse(user, db)
  body = verse['body']
  attempt = get_input(verse['reference'])
  reprompt = check_answer(body, attempt)  #returns '' for success, else returns prompt for next attempt
  success = false
  success = true if reprompt.empty?
  while(!reprompt.empty?)
    attempt = reprompt + ' ' + get_input(reprompt)
    reprompt = check_answer(body, attempt)
  end
  
  update_verse_record(verse, success, db)
  list(username)
end
#############   PROGRAM STARTS HERE    #####################

#puts ARGV[0]

if ARGV.size < 1 || ARGV[0]=='help'
  help()
else
  case ARGV[0].downcase
  when 'new'
    new_verse()
  when 'quiz'
    quiz()
  when 'list'
    list()
  when 'add'
    if ARGV[1].downcase == 'user'
      add_user()
    else
      help()
    end
  else
    help()
  end
end